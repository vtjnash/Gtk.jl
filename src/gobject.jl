abstract GObjectI
typealias GObject GObjectI

# Alternative object construction style. This would let us share constructors
# by creating const aliases: `const Z = GObject{:Z}`
type GObjectAny <: GObjectI
    handle::Ptr{GObject}
    GObjectAny(handle::Ptr{GObject}) = (handle != C_NULL ? gc_ref(new(handle)) : error("Cannot construct $gname with a NULL pointer"))
end


macro quark_str(q)
    :( ccall((:g_quark_from_string, libglib), Uint32, (Ptr{Uint8},), bytestring($q)) )
end
const jlref_quark = quark"julia_ref"

# All GtkWidgets are expected to have a 'handle' field
# of type Ptr{GObjectI} corresponding to the Gtk object
# and an 'all' field which has type GdkRectangle
# corresponding to the rectangle allocated to the object,
# or to override the size, width, and height methods
convert(::Type{Ptr{GObjectI}},w::GObjectI) = w.handle
convert{T<:GObjectI}(::Type{T},w::Ptr{T}) = convert(T,convert(Ptr{GObjectI},w))
function convert{T<:GObjectI}(::Type{T},w::Ptr{GObjectI})
    x = ccall((:g_object_get_qdata, libgobject), Ptr{GObjectI}, (Ptr{GObjectI},Uint32), w, jlref_quark)
    x == C_NULL && error("GObject didn't have a corresponding Julia object")
    unsafe_pointer_to_objref(x)::T
end
### Garbage collection [prevention]
const gc_preserve = ObjectIdDict() # reference counted closures
function gc_ref(x::ANY)
    global gc_preserve
    gc_preserve[x] = (get(gc_preserve, x, 0)::Int)+1
    x
end
function gc_unref(x::ANY)
    global gc_preserve
    count = get(gc_preserve, x, 0)::Int-1
    if count <= 0
        delete!(gc_preserve, x)
    end
    nothing
end
gc_ref_closure{T}(x::T) = (gc_ref(x);cfunction(gc_unref, Void, (T, Ptr{Void})))
gc_unref(x::Any, ::Ptr{Void}) = gc_unref(x)

const gc_preserve_gtk = ObjectIdDict() # gtk objects
function gc_ref{T<:GObjectI}(x::T)
    global gc_preserve_gtk
    addref = function()
        ccall((:g_object_ref_sink,libgobject),Ptr{GObjectI},(Ptr{GObjectI},),x)
        finalizer(x,function(x)
                global gc_preserve_gtk
                ccall((:g_object_unref,libgobject),Void,(Ptr{GObjectI},),x)
                gc_preserve_gtk[WeakRef(x)] = x #convert to a strong-reference
            end)
        wx = WeakRef(x) # record the existence of the object, but allow the finalizer
        gc_preserve_gtk[wx] = wx
    end
    ref = get(gc_preserve_gtk,x,nothing)
    if isa(ref,Nothing)
        ccall((:g_object_set_qdata_full, libgobject), Void,
            (Ptr{GObjectI}, Uint32, Any, Ptr{Void}), x, jlref_quark, x, 
            cfunction(gc_unref, Void, (T,))) # add a circular reference to the Julia object in the GObjectI
        addref()
    elseif !isa(ref,WeakRef)
        # oops, we previously deleted the link, but now it's back
        addref()
    else
        # already gc-protected, nothing to do
    end
    x
end


function gc_unref(x::GObjectI)
    # this strongly destroys and invalidates the object
    # it is intended to be called by Gtk, not in user code function
    global gc_preserve_gtk
    ccall((:g_object_steal_qdata,libgobject),Ptr{Any},(Ptr{GObjectI},Uint32),x,jlref_quark)
    delete!(gc_preserve_gtk, x)
    x.handle = C_NULL
    nothing
end
gc_unref(::Ptr{GObjectI}, x::GObjectI) = gc_unref(x)
gc_ref_closure(x::GObjectI) = C_NULL

typealias Enum Int32
