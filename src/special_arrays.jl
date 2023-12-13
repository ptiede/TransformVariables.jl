export UnitVector, UnitSimplex, CorrCholeskyFactor, corr_cholesky_factor

####
#### building blocks
####

"""
$(SIGNATURES)

`log(abs(…))` of the derivative of `tanh`, calculated accurately.
"""
function _tanh_logabsderiv(x)
    d = 2*x
    log(4) + d - 2 * log1pexp(d)
end

"""
    (y, r, ℓ) = $SIGNATURES

Given ``x ∈ ℝ`` and ``0 ≤ r ≤ 1``, return `(y, r′)` such that

1. ``y² + (r′)² = r²``,

2. ``y: |y| ≤ r`` is mapped with a bijection from `x`.

`ℓ` is the log Jacobian (whether it is evaluated depends on `flag`).
"""
@inline function l2_remainder_transform(flag::LogJacFlag, x, r)
    # note that 1-tanh(x)^2 = sech(x)^2
    (tanh(x) * √r, r*sech(x)^2,
     flag isa NoLogJac ? flag : _tanh_logabsderiv(x) + 0.5*log(r))
end

"""
    (x, r′) = $SIGNATURES

Inverse of [`l2_remainder_transform`](@ref) in `x` and `y`.
"""
@inline l2_remainder_inverse(y, r) = atanh(y/√r), r-y^2

####
#### UnitVector
####

"""
    UnitVector(n)

Transform `n-1` real numbers to a unit vector of length `n`, under the
Euclidean norm.
"""
struct UnitVector <: VectorTransform
    n::Int
    function UnitVector(n::Int)
        @argcheck n ≥ 1 "Dimension should be positive."
        new(n)
    end
end

dimension(t::UnitVector) = t.n - 1

function _summary_rows(transformation::UnitVector, mime)
    _summary_row(transformation, "$(transformation.n) element unit vector transformation")
end

function transform_with(flag::LogJacFlag, t::UnitVector, x::AbstractVector, index)
    @unpack n = t
    T = robust_eltype(x)
    r = one(T)
    y = Vector{T}(undef, n)
    ℓ = logjac_zero(flag, T)
    @inbounds for i in 1:(n - 1)
        xi = x[index]
        index += 1
        y[i], r, ℓi = l2_remainder_transform(flag, xi, r)
        ℓ += ℓi
    end
    y[end] = √r
    y, ℓ, index
end

inverse_eltype(t::UnitVector, y::AbstractVector) = robust_eltype(y)

function inverse_at!(x::AbstractVector, index, t::UnitVector, y::AbstractVector)
    @unpack n = t
    @argcheck length(y) == n
    r = one(eltype(y))
    @inbounds for yi in axes(y, 1)[1:(end-1)]
        x[index], r = l2_remainder_inverse(y[yi], r)
        index += 1
    end
    index
end


####
#### UnitSimplex
####

"""
    UnitSimplex(n)

Transform `n-1` real numbers to a vector of length `n` whose elements are non-negative and sum to one.
"""
struct UnitSimplex <: VectorTransform
    n::Int
    function UnitSimplex(n::Int)
        @argcheck n ≥ 1 "Dimension should be positive."
        new(n)
    end
end

function _summary_rows(transformation::UnitSimplex, mime)
    _summary_row(transformation, "$(transformation.n) element unit simplex transformation")
end

dimension(t::UnitSimplex) = t.n - 1

function transform_with(flag::LogJacFlag, t::UnitSimplex, x::AbstractVector, index)
    @unpack n = t
    T = robust_eltype(x)

    ℓ = logjac_zero(flag, T)
    stick = one(T)
    y = Vector{T}(undef, n)
    @inbounds for i in 1:n-1
        xi = x[index]
        index += 1
        z = logistic(xi - log(n-i))
        y[i] = z * stick

        if !(flag isa NoLogJac)
            ℓ += log(stick) - logit_logjac(z)
        end

        stick *= 1 - z
    end

    y[end] = stick

    y, ℓ, index
end

inverse_eltype(t::UnitSimplex, y::AbstractVector) = robust_eltype(y)

function inverse_at!(x::AbstractVector, index, t::UnitSimplex, y::AbstractVector)
    @unpack n = t
    @argcheck length(y) == n

    stick = one(eltype(y))
    @inbounds for i in axes(y, 1)[1:end-1]
        z = y[i]/stick
        x[index] = logit(z) + log(n-i)
        stick -= y[i]
        index += 1
    end
    index
end

####
#### correlation cholesky factor
####

"""
    CorrCholeskyFactor(n)

!!! note
    It is better style to use [`corr_cholesky_factor`](@ref), this will be deprecated.

Cholesky factor of a correlation matrix of size `n`.

Transforms ``n×(n-1)/2`` real numbers to an ``n×n`` upper-triangular matrix `U`, such that
`U'*U` is a correlation matrix (positive definite, with unit diagonal).

# Notes

If

- `z` is a vector of `n` IID standard normal variates,

- `σ` is an `n`-element vector of standard deviations,

- `U` is obtained from `CorrCholeskyFactor(n)`,

then `Diagonal(σ) * U' * z` will be a multivariate normal with the given variances and
correlation matrix `U' * U`.
"""
struct CorrCholeskyFactor <: VectorTransform
    n::Int
    function CorrCholeskyFactor(n)
        @argcheck n ≥ 1 "Dimension should be positive."
        new(n)
    end
end

function _summary_rows(transformation::CorrCholeskyFactor, mime)
    @unpack n = transformation
    _summary_row(transformation, "$(n)×$(n) correlation cholesky factor")
end


"""
$(SIGNATURES)

Transform into a Cholesky factor of a correlation matrix.

If the argument is a (positive) integer `n`, it determines the size of the output `n × n`,
resulting in a `Matrix`.

If the argument is `SMatrix{N,N}`, an `SMatrix` is produced.
"""
function corr_cholesky_factor(n::Int)
    @argcheck n ≥ 1 "Dimension should be positive."
    CorrCholeskyFactor(n)
end

dimension(t::CorrCholeskyFactor) = unit_triangular_dimension(t.n)

result_size(transformation::CorrCholeskyFactor) = transformation.n

"Static version of cholesky correlation factor."
struct StaticCorrCholeskyFactor{D,S} <: VectorTransform end

function _summary_rows(transformation::StaticCorrCholeskyFactor{D,S}, mime) where {D,S}
    _summary_row(transformation, "SMatrix{$(S),$(S)} correlation cholesky factor")
end


result_size(::StaticCorrCholeskyFactor{D,S}) where {D,S} = S

function corr_cholesky_factor(::Type{SMatrix{S,S}}) where S
    D = unit_triangular_dimension(S)
    StaticCorrCholeskyFactor{D,S}()
end

dimension(transformation::StaticCorrCholeskyFactor{D}) where D = D

"""
$(SIGNATURES)

Implementation of Cholesky factor calculation.
"""
function calculate_corr_cholesky_factor!(U::AbstractMatrix{T}, flag::LogJacFlag,
                                          x::AbstractVector, index::Int) where {T<:Real}
    n = size(U, 1)
    ℓ = logjac_zero(flag, T)
    @inbounds for col_index in 1:n
        r = one(T)
        for row_index in 1:(col_index-1)
            xi = x[index]
            U[row_index, col_index], r, ℓi = l2_remainder_transform(flag, xi, r)
            ℓ += ℓi
            index += 1
        end
        U[col_index, col_index] = √r
    end
    U, ℓ, index
end

function transform_with(flag::LogJacFlag, t::CorrCholeskyFactor, x::AbstractVector{T},
                        index) where T
    n = result_size(t)
    U, ℓ, index′ = calculate_corr_cholesky_factor!(Matrix{robust_eltype(x)}(undef, n, n),
                                                    flag, x, index)
    UpperTriangular(U), ℓ, index′
end

function transform_with(flag::LogJacFlag, transformation::StaticCorrCholeskyFactor{D,S},
                        x::AbstractVector{T}, index) where {D,S,T}
    # NOTE: add an unrolled version for small sizes
    E = robust_eltype(x)
    U = if isbitstype(E)
        zero(MMatrix{S,S,robust_eltype(x)})
    else
        # NOTE: currently allocating because non-bitstype based AD (eg ReverseDiff) does not work with MMatrix
        zeros(E, S, S)
    end
    U, ℓ, index′ = calculate_corr_cholesky_factor!(U, flag, x, index)
    UpperTriangular(SMatrix{S,S}(U)), ℓ, index′
end

inverse_eltype(t::Union{CorrCholeskyFactor,StaticCorrCholeskyFactor}, U::UpperTriangular) = robust_eltype(U)

function inverse_at!(x::AbstractVector, index,
                     t::Union{CorrCholeskyFactor,StaticCorrCholeskyFactor}, U::UpperTriangular)
    n = result_size(t)
    @argcheck size(U, 1) == n
    @inbounds for col in 1:n
        r = one(eltype(U))
        for row in 1:(col-1)
            x[index], r = l2_remainder_inverse(U[row, col], r)
            index += 1
        end
    end
    index
end
