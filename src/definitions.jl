# This file was formerly a part of Julia. License is MIT: https://julialang.org/license

using LinearAlgebra
using LinearAlgebra: BlasReal
import Base: show, summary, size, ndims, length, eltype,
             *, inv, \, size, step, getindex, iterate

# DFT plan where the inputs are an array of eltype T
abstract type Plan{T} end

eltype(::Type{<:Plan{T}}) where {T} = T

# size(p) should return the size of the input array for p
size(p::Plan, d) = size(p)[d]
ndims(p::Plan) = length(size(p))
length(p::Plan) = prod(size(p))::Int

fftfloat(x) = _fftfloat(float(x))
_fftfloat(::Type{T}) where {T<:BlasReal} = T
_fftfloat(::Type{Float16}) = Float32
_fftfloat(::Type{Complex{T}}) where {T} = Complex{_fftfloat(T)}
_fftfloat(::Type{T}) where {T} = error("type $T not supported")
_fftfloat(x::T) where {T} = _fftfloat(T)(x)

complexfloat(x::StridedArray{Complex{<:BlasReal}}) = x
realfloat(x::StridedArray{<:BlasReal}) = x

# return an Array, rather than similar(x), to avoid an extra copy for FFTW
# (which only works on StridedArray types).
complexfloat(x::AbstractArray{T}) where {T<:Complex} = copy1(typeof(fftfloat(zero(T))), x)
complexfloat(x::AbstractArray{T}) where {T<:Real} = copy1(typeof(complex(fftfloat(zero(T)))), x)

realfloat(x::AbstractArray{T}) where {T<:Real} = copy1(typeof(fftfloat(zero(T))), x)

# copy to a 1-based array, using circular permutation
function copy1(::Type{T}, x) where T
    y = Array{T}(undef, map(length, axes(x)))
    Base.circcopy!(y, x)
end

to1(x::AbstractArray) = _to1(axes(x), x)
_to1(::Tuple{Base.OneTo,Vararg{Base.OneTo}}, x) = x
_to1(::Tuple, x) = copy1(eltype(x), x)

# implementations only need to provide plan_X(x, region)
# for X in (:fft, :bfft, ...):
for f in (:fft, :bfft, :ifft, :fft!, :bfft!, :ifft!, :rfft)
    pf = Symbol("plan_", f)
    @eval begin
        $f(x::AbstractArray) = (y = to1(x); $pf(y) * y)
        $f(x::AbstractArray, region) = (y = to1(x); $pf(y, region) * y)
        $pf(x::AbstractArray; kws...) = (y = to1(x); $pf(y, 1:ndims(y); kws...))
    end
end

"""
    plan_ifft(A [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Same as [`plan_fft`](@ref), but produces a plan that performs inverse transforms
[`ifft`](@ref).
"""
plan_ifft

"""
    plan_ifft!(A [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Same as [`plan_ifft`](@ref), but operates in-place on `A`.
"""
plan_ifft!

"""
    plan_bfft!(A [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Same as [`plan_bfft`](@ref), but operates in-place on `A`.
"""
plan_bfft!

"""
    plan_bfft(A [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Same as [`plan_fft`](@ref), but produces a plan that performs an unnormalized
backwards transform [`bfft`](@ref).
"""
plan_bfft

"""
    plan_fft(A [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Pre-plan an optimized FFT along given dimensions (`dims`) of arrays matching the shape and
type of `A`.  (The first two arguments have the same meaning as for [`fft`](@ref).)
Returns an object `P` which represents the linear operator computed by the FFT, and which
contains all of the information needed to compute `fft(A, dims)` quickly.

To apply `P` to an array `A`, use `P * A`; in general, the syntax for applying plans is much
like that of matrices.  (A plan can only be applied to arrays of the same size as the `A`
for which the plan was created.)  You can also apply a plan with a preallocated output array `Â`
by calling `mul!(Â, plan, A)`.  (For `mul!`, however, the input array `A` must
be a complex floating-point array like the output `Â`.) You can compute the inverse-transform plan by `inv(P)`
and apply the inverse plan with `P \\ Â` (the inverse plan is cached and reused for
subsequent calls to `inv` or `\\`), and apply the inverse plan to a pre-allocated output
array `A` with `ldiv!(A, P, Â)`.

The `flags` argument is a bitwise-or of FFTW planner flags, defaulting to `FFTW.ESTIMATE`.
e.g. passing `FFTW.MEASURE` or `FFTW.PATIENT` will instead spend several seconds (or more)
benchmarking different possible FFT algorithms and picking the fastest one; see the FFTW
manual for more information on planner flags.  The optional `timelimit` argument specifies a
rough upper bound on the allowed planning time, in seconds. Passing `FFTW.MEASURE` or
`FFTW.PATIENT` may cause the input array `A` to be overwritten with zeros during plan
creation.

[`plan_fft!`](@ref) is the same as [`plan_fft`](@ref) but creates a
plan that operates in-place on its argument (which must be an array of complex
floating-point numbers). [`plan_ifft`](@ref) and so on are similar but produce
plans that perform the equivalent of the inverse transforms [`ifft`](@ref) and so on.
"""
plan_fft

"""
    plan_fft!(A [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Same as [`plan_fft`](@ref), but operates in-place on `A`.
"""
plan_fft!

"""
    rfft(A [, dims])

Multidimensional FFT of a real array `A`, exploiting the fact that the transform has
conjugate symmetry in order to save roughly half the computational time and storage costs
compared with [`fft`](@ref). If `A` has size `(n_1, ..., n_d)`, the result has size
`(div(n_1,2)+1, ..., n_d)`.

The optional `dims` argument specifies an iterable subset of one or more dimensions of `A`
to transform, similar to [`fft`](@ref). Instead of (roughly) halving the first
dimension of `A` in the result, the `dims[1]` dimension is (roughly) halved in the same way.
"""
rfft

"""
    ifft!(A [, dims])

Same as [`ifft`](@ref), but operates in-place on `A`.
"""
ifft!

"""
    ifft(A [, dims])

Multidimensional inverse FFT.

A one-dimensional inverse FFT computes

```math
\\operatorname{IDFT}(A)[k] = \\frac{1}{\\operatorname{length}(A)}
\\sum_{n=1}^{\\operatorname{length}(A)} \\exp\\left(+i\\frac{2\\pi (n-1)(k-1)}
{\\operatorname{length}(A)} \\right) A[n].
```

A multidimensional inverse FFT simply performs this operation along each transformed dimension of `A`.
"""
ifft

"""
    fft!(A [, dims])

Same as [`fft`](@ref), but operates in-place on `A`, which must be an array of
complex floating-point numbers.
"""
fft!

"""
    bfft(A [, dims])

Similar to [`ifft`](@ref), but computes an unnormalized inverse (backward)
transform, which must be divided by the product of the sizes of the transformed dimensions
in order to obtain the inverse. (This is slightly more efficient than [`ifft`](@ref)
because it omits a scaling step, which in some applications can be combined with other
computational steps elsewhere.)

```math
\\operatorname{BDFT}(A)[k] = \\operatorname{length}(A) \\operatorname{IDFT}(A)[k]
```
"""
bfft

"""
    bfft!(A [, dims])

Same as [`bfft`](@ref), but operates in-place on `A`.
"""
bfft!

# promote to a complex floating-point type (out-of-place only),
# so implementations only need Complex{Float} methods
for f in (:fft, :bfft, :ifft)
    pf = Symbol("plan_", f)
    @eval begin
        $f(x::AbstractArray{<:Real}, region=1:ndims(x)) = $f(complexfloat(x), region)
        $pf(x::AbstractArray{<:Real}, region; kws...) = $pf(complexfloat(x), region; kws...)
        $f(x::AbstractArray{<:Complex{<:Union{Integer,Rational}}}, region=1:ndims(x)) = $f(complexfloat(x), region)
        $pf(x::AbstractArray{<:Complex{<:Union{Integer,Rational}}}, region; kws...) = $pf(complexfloat(x), region; kws...)
    end
end
rfft(x::AbstractArray{<:Union{Integer,Rational}}, region=1:ndims(x)) = rfft(realfloat(x), region)
plan_rfft(x::AbstractArray, region; kws...) = plan_rfft(realfloat(x), region; kws...)

# only require implementation to provide *(::Plan{T}, ::Array{T})
*(p::Plan{T}, x::AbstractArray) where {T} = p * copy1(T, x)

# Implementations should also implement mul!(Y, plan, X) so as to support
# pre-allocated output arrays.  We don't define * in terms of mul!
# generically here, however, because of subtleties for in-place and rfft plans.

##############################################################################
# To support inv, \, and ldiv!(y, p, x), we require Plan subtypes
# to have a pinv::Plan field, which caches the inverse plan, and which
# should be initially undefined.  They should also implement
# plan_inv(p) to construct the inverse of a plan p.

# hack from @simonster (in #6193) to compute the return type of plan_inv
# without actually calling it or even constructing the empty arrays.
_pinv_type(p::Plan) = typeof([plan_inv(x) for x in typeof(p)[]])
pinv_type(p::Plan) = eltype(_pinv_type(p))

inv(p::Plan) =
    isdefined(p, :pinv) ? p.pinv::pinv_type(p) : (p.pinv = plan_inv(p))
\(p::Plan, x::AbstractArray) = inv(p) * x
LinearAlgebra.ldiv!(y::AbstractArray, p::Plan, x::AbstractArray) = LinearAlgebra.mul!(y, inv(p), x)

##############################################################################
# implementations only need to provide the unnormalized backwards FFT,
# similar to FFTW, and we do the scaling generically to get the ifft:

mutable struct ScaledPlan{T,P,N} <: Plan{T}
    p::P
    scale::N # not T, to avoid unnecessary promotion to Complex
    pinv::Plan
    ScaledPlan{T,P,N}(p, scale) where {T,P,N} = new(p, scale)
end
ScaledPlan{T}(p::P, scale::N) where {T,P,N} = ScaledPlan{T,P,N}(p, scale)
ScaledPlan(p::Plan{T}, scale::Number) where {T} = ScaledPlan{T}(p, scale)
ScaledPlan(p::ScaledPlan, α::Number) = ScaledPlan(p.p, p.scale * α)

size(p::ScaledPlan) = size(p.p)

show(io::IO, p::ScaledPlan) = print(io, p.scale, " * ", p.p)
summary(p::ScaledPlan) = string(p.scale, " * ", summary(p.p))

*(p::ScaledPlan, x::AbstractArray) = LinearAlgebra.rmul!(p.p * x, p.scale)

*(α::Number, p::Plan) = ScaledPlan(p, α)
*(p::Plan, α::Number) = ScaledPlan(p, α)
*(I::UniformScaling, p::ScaledPlan) = ScaledPlan(p, I.λ)
*(p::ScaledPlan, I::UniformScaling) = ScaledPlan(p, I.λ)
*(I::UniformScaling, p::Plan) = ScaledPlan(p, I.λ)
*(p::Plan, I::UniformScaling) = ScaledPlan(p, I.λ)

# Normalization for ifft, given unscaled bfft, is 1/prod(dimensions)
normalization(::Type{T}, sz, region) where T = one(T) / Int(prod(sz[r] for r in region))::Int
normalization(X, region) = normalization(real(eltype(X)), size(X), region)

plan_ifft(x::AbstractArray, region; kws...) =
    ScaledPlan(plan_bfft(x, region; kws...), normalization(x, region))
plan_ifft!(x::AbstractArray, region; kws...) =
    ScaledPlan(plan_bfft!(x, region; kws...), normalization(x, region))

plan_inv(p::ScaledPlan) = ScaledPlan(plan_inv(p.p), inv(p.scale))

LinearAlgebra.mul!(y::AbstractArray, p::ScaledPlan, x::AbstractArray) =
    LinearAlgebra.lmul!(p.scale, LinearAlgebra.mul!(y, p.p, x))

##############################################################################
# Real-input DFTs are annoying because the output has a different size
# than the input if we want to gain the full factor-of-two(ish) savings
# For backward real-data transforms, we must specify the original length
# of the first dimension, since there is no reliable way to detect this
# from the data (we can't detect whether the dimension was originally even
# or odd).

for f in (:brfft, :irfft)
    pf = Symbol("plan_", f)
    @eval begin
        $f(x::AbstractArray, d::Integer) = $pf(x, d) * x
        $f(x::AbstractArray, d::Integer, region) = $pf(x, d, region) * x
        $pf(x::AbstractArray, d::Integer;kws...) = $pf(x, d, 1:ndims(x);kws...)
    end
end

for f in (:brfft, :irfft)
    @eval begin
        $f(x::AbstractArray{<:Real}, d::Integer, region=1:ndims(x)) = $f(complexfloat(x), d, region)
        $f(x::AbstractArray{<:Complex{<:Union{Integer,Rational}}}, d::Integer, region=1:ndims(x)) = $f(complexfloat(x), d, region)
    end
end

"""
    irfft(A, d [, dims])

Inverse of [`rfft`](@ref): for a complex array `A`, gives the corresponding real
array whose FFT yields `A` in the first half. As for [`rfft`](@ref), `dims` is an
optional subset of dimensions to transform, defaulting to `1:ndims(A)`.

`d` is the length of the transformed real array along the `dims[1]` dimension, which must
satisfy `div(d,2)+1 == size(A,dims[1])`. (This parameter cannot be inferred from `size(A)`
since both `2*size(A,dims[1])-2` as well as `2*size(A,dims[1])-1` are valid sizes for the
transformed real array.)
"""
irfft

"""
    brfft(A, d [, dims])

Similar to [`irfft`](@ref) but computes an unnormalized inverse transform (similar
to [`bfft`](@ref)), which must be divided by the product of the sizes of the
transformed dimensions (of the real output array) in order to obtain the inverse transform.
"""
brfft

rfft_output_size(x::AbstractArray, region) = rfft_output_size(size(x), region)
function rfft_output_size(sz::Dims{N}, region) where {N}
    d1 = first(region)
    return ntuple(d -> d == d1 ? sz[d]>>1 + 1 : sz[d], Val(N))
end

brfft_output_size(x::AbstractArray, d::Integer, region) = brfft_output_size(size(x), d, region)
function brfft_output_size(sz::Dims{N}, d::Integer, region) where {N}
    d1 = first(region)
    @assert sz[d1] == d>>1 + 1
    return ntuple(i -> i == d1 ? d : sz[i], Val(N))
end

plan_irfft(x::AbstractArray{Complex{T}}, d::Integer, region; kws...) where {T} =
    ScaledPlan(plan_brfft(x, d, region; kws...),
               normalization(T, brfft_output_size(x, d, region), region))

"""
    plan_irfft(A, d [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Pre-plan an optimized inverse real-input FFT, similar to [`plan_rfft`](@ref)
except for [`irfft`](@ref) and [`brfft`](@ref), respectively. The first
three arguments have the same meaning as for [`irfft`](@ref).
"""
plan_irfft

##############################################################################

"""
    fftshift(x, [dim])

Circular-shift along the given dimension of a periodic signal `x` centered at
index `1` so it becomes centered at index `N÷2+1`, where `N` is the size of
that dimension.

This can be undone with [`ifftshift`](@ref). For even `N` this is equivalent to
swapping the first and second halves, so `fftshift` and [`ifftshift`](@ref) are
the same.

If `dim` is not given then the signal is shifted along each dimension.
"""
fftshift

function fftshift(x, dim = 1:ndims(x))
    s = ntuple(d -> d in dim ? div(size(x,d),2) : 0, Val(ndims(x)))
    circshift(x, s)
end

"""
    ifftshift(x, [dim])

Circular-shift along the given dimension of a periodic signal `x` centered at
index `N÷2+1` so it becomes centered at index `1`, where `N` is the size of
that dimension.

This undoes the effect of [`fftshift`](@ref). For even `N` this is equivalent to
swapping the first and second halves, so [`fftshift`](@ref) and `ifftshift` are
the same.

If `dim` is not given then the signal is shifted along each dimension.
"""
ifftshift

function ifftshift(x, dim = 1:ndims(x))
    s = ntuple(d -> d in dim ? -div(size(x,d),2) : 0, Val(ndims(x)))
    circshift(x, s)
end

##############################################################################


struct Frequencies{T<:Number} <: AbstractVector{T}
    n_nonnegative::Int
    n::Int
    multiplier::T

    Frequencies(n_nonnegative::Int, n::Int, multiplier::T) where {T<:Number} = begin
        1 ≤ n_nonnegative ≤ n || throw(ArgumentError("Condition 1 ≤ n_nonnegative ≤ n isn't satisfied."))
        return new{T}(n_nonnegative, n, multiplier)
    end
end

unsafe_getindex(x::Frequencies, i::Int) =
    (i-1-ifelse(i <= x.n_nonnegative, 0, x.n))*x.multiplier
@inline function Base.getindex(x::Frequencies, i::Int)
    @boundscheck Base.checkbounds(x, i)
    unsafe_getindex(x, i)
end

function Base.iterate(x::Frequencies, i::Int=1)
    i > x.n ? nothing : (unsafe_getindex(x,i), i + 1)
end
Base.size(x::Frequencies) = (x.n,)
Base.step(x::Frequencies) = x.multiplier

Base.copy(x::Frequencies) = x

# Retain the lazy representation upon scalar multiplication
Broadcast.broadcasted(::typeof(*), f::Frequencies, x::Number) = Frequencies(f.n_nonnegative, f.n, f.multiplier * x)
Broadcast.broadcasted(::typeof(*), x::Number, f::Frequencies) = Broadcast.broadcasted(*, f, x)
Broadcast.broadcasted(::typeof(/), f::Frequencies, x::Number) = Frequencies(f.n_nonnegative, f.n, f.multiplier / x)
Broadcast.broadcasted(::typeof(\), x::Number, f::Frequencies) = Broadcast.broadcasted(/, f, x)

Base.maximum(f::Frequencies{T}) where T = (f.n_nonnegative - ifelse(f.multiplier >= zero(T), 1, f.n)) * f.multiplier
Base.minimum(f::Frequencies{T}) where T = (f.n_nonnegative - ifelse(f.multiplier >= zero(T), f.n, 1)) * f.multiplier
Base.extrema(f::Frequencies) = (minimum(f), maximum(f))

"""
    fftfreq(n, fs=1)
Return the discrete Fourier transform (DFT) sample frequencies for a DFT of length `n`. The returned
`Frequencies` object is an `AbstractVector` containing the frequency
bin centers at every sample point. `fs` is the sampling rate of the
input signal, which is the reciprocal of the sample spacing.

Given a window of length `n` and a sampling rate `fs`, the frequencies returned are

```julia
[0:n÷2-1; -n÷2:-1]  * fs/n   # if n is even
[0:(n-1)÷2; -(n-1)÷2:-1]  * fs/n  # if n is odd
```

# Examples

```jldoctest; setup=:(using AbstractFFTs)
julia> fftfreq(4, 1)
4-element Frequencies{Float64}:
  0.0
  0.25
 -0.5
 -0.25

julia> fftfreq(5, 2)
5-element Frequencies{Float64}:
  0.0
  0.4
  0.8
 -0.8
 -0.4
```
"""
fftfreq(n::Int, fs::Number=1) = Frequencies((n+1) >> 1, n, fs/n)

"""
    rfftfreq(n, fs=1)
Return the discrete Fourier transform (DFT) sample frequencies for a real DFT of length `n`.
The returned `Frequencies` object is an `AbstractVector`
containing the frequency bin centers at every sample point. `fs`
is the sampling rate of the input signal, which is the reciprocal of the sample spacing.

Given a window of length `n` and a sampling rate `fs`, the frequencies returned are

```julia
[0:n÷2;]  * fs/n  # if n is even
[0:(n-1)÷2;]  * fs/n  # if n is odd
```

!!! note
    The Nyquist-frequency component is considered to be positive, unlike [`fftfreq`](@ref).

# Examples

```jldoctest; setup=:(using AbstractFFTs)
julia> rfftfreq(4, 1)
3-element Frequencies{Float64}:
 0.0
 0.25
 0.5

julia> rfftfreq(5, 2)
3-element Frequencies{Float64}:
 0.0
 0.4
 0.8
```
"""
rfftfreq(n::Int, fs::Number=1) = Frequencies((n >> 1)+1, (n >> 1)+1, fs/n)

fftshift(x::Frequencies) = (x.n_nonnegative-x.n:x.n_nonnegative-1)*x.multiplier


##############################################################################

"""
    fft(A [, dims])

Performs a multidimensional FFT of the array `A`. The optional `dims` argument specifies an
iterable subset of dimensions (e.g. an integer, range, tuple, or array) to transform along.
Most efficient if the size of `A` along the transformed dimensions is a product of small
primes; see `Base.nextprod`. See also [`plan_fft()`](@ref) for even greater efficiency.

A one-dimensional FFT computes the one-dimensional discrete Fourier transform (DFT) as
defined by

```math
\\operatorname{DFT}(A)[k] =
  \\sum_{n=1}^{\\operatorname{length}(A)}
  \\exp\\left(-i\\frac{2\\pi
  (n-1)(k-1)}{\\operatorname{length}(A)} \\right) A[n].
```

A multidimensional FFT simply performs this operation along each transformed dimension of `A`.

!!! note
    This performs a multidimensional FFT by default. FFT libraries in other languages such as
    Python and Octave perform a one-dimensional FFT along the first non-singleton dimension
    of the array. This is worth noting while performing comparisons.
"""
fft

"""
    plan_rfft(A [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Pre-plan an optimized real-input FFT, similar to [`plan_fft`](@ref) except for
[`rfft`](@ref) instead of [`fft`](@ref). The first two arguments, and the
size of the transformed result, are the same as for [`rfft`](@ref).
"""
plan_rfft

"""
    plan_brfft(A, d [, dims]; flags=FFTW.ESTIMATE, timelimit=Inf)

Pre-plan an optimized real-input unnormalized transform, similar to
[`plan_rfft`](@ref) except for [`brfft`](@ref) instead of
[`rfft`](@ref). The first two arguments and the size of the transformed result, are
the same as for [`brfft`](@ref).
"""
plan_brfft
