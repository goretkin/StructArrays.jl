using StructArrays
using StructArrays: staticschema, iscompatible, _promote_typejoin, append!!
using OffsetArrays: OffsetArray
import Tables, PooledArrays, WeakRefStrings
using TypedTables: Table
using DataAPI: refarray, refvalue
using Adapt: adapt, Adapt
using Test

using Documenter: doctest
doctest(StructArrays)


@testset "index" begin
    a, b = [1 2; 3 4], [4 5; 6 7]
    t = StructArray((a = a, b = b))
    @test (@inferred t[2,2]) == (a = 4, b = 7)
    @test (@inferred t[2,1:2]) == StructArray((a = [3, 4], b = [6, 7]))
    @test_throws BoundsError t[3,3]
    @test (@inferred view(t, 2, 1:2)) == StructArray((a = view(a, 2, 1:2), b = view(b, 2, 1:2)))
end

@testset "components" begin
    t = StructArray(a = 1:10, b = rand(Bool, 10))
    @test StructArrays.propertynames(t) == (:a, :b)
    @test StructArrays.propertynames(StructArrays.components(t)) == (:a, :b)
end

@testset "utils" begin
    t = StructArray(rand(ComplexF64, 2, 2))
    T = staticschema(eltype(t))
    @test StructArrays.eltypes(T) == NamedTuple{(:re, :im), Tuple{Float64, Float64}}
    @test StructArrays.map_params(eltype, T) == NamedTuple{(:re, :im), Tuple{Float64, Float64}}
    @test StructArrays.map_params(eltype, StructArrays.astuple(T)) == Tuple{Float64, Float64}
    @test !iscompatible(typeof((1, 2)), typeof(([1],)))
    @test iscompatible(typeof((1, 2)), typeof(([1], [2])))
    @test !iscompatible(typeof((1, 2)), typeof(([1.1], [2])))
    @test iscompatible(typeof(()), typeof(()))
    @test _promote_typejoin(Tuple{Int, Missing}, Tuple{Int, Int}) == Tuple{Int, Union{Int, Missing}}
    @test _promote_typejoin(Pair{Int, Missing}, Pair{Int, Int}) == Pair{Int, Union{Int, Missing}}
    @test _promote_typejoin(NamedTuple{(:a, :b), Tuple{Int, Missing}}, NamedTuple{(:a, :b), Tuple{Int, Int}}) == NamedTuple{(:a, :b), Tuple{Int, Union{Int, Missing}}}
    @test _promote_typejoin(Tuple{}, Tuple{}) == Tuple{}
    @test _promote_typejoin(Tuple{Int}, Tuple{Int, Int}) == Tuple{Int, Vararg{Int, N} where N}

    @test StructArrays.astuple(Tuple{Int}) == Tuple{Int}
    @test StructArrays.strip_params(Tuple{Int}) == Tuple
    @test StructArrays.astuple(NamedTuple{(:a,), Tuple{Float64}}) == Tuple{Float64}
    @test StructArrays.strip_params(NamedTuple{(:a,), Tuple{Float64}}) == NamedTuple{(:a,)}
end

@testset "indexstyle" begin
    @inferred IndexStyle(StructArray(a=rand(10,10), b=view(rand(100,100), 1:10, 1:10)))
    s = StructArray(a=rand(10,10), b=view(rand(100,100), 1:10, 1:10))
    T = typeof(s)
    @test IndexStyle(T) === IndexCartesian()
    @test StructArrays.index_type(T) == CartesianIndex{2}
    @test s[100] == s[10, 10] == (a=s.a[10,10], b=s.b[10,10])
    s[100] = (a=1, b=1)
    @test s[100] == s[10, 10] == (a=1, b=1)
    s[10, 10] = (a=0, b=0)
    @test s[100] == s[10, 10] == (a=0, b=0)
    @inferred IndexStyle(StructArray(a=rand(10,10), b=rand(10,10)))
    s = StructArray(a=rand(10,10), b=rand(10,10))
    T = typeof(s)
    @test IndexStyle(T) === IndexLinear()
    @test StructArrays.index_type(T) == Int
    @test s[100] == s[10, 10] == (a=s.a[10,10], b=s.b[10,10])
    s[100] = (a=1, b=1)
    @test s[100] == s[10, 10] == (a=1, b=1)
    s[10, 10] = (a=0, b=0)
    @test s[100] == s[10, 10] == (a=0, b=0)
end

@testset "replace_storage" begin
    v = StructArray(a=rand(10), b = fill("string", 10))
    v_pooled = StructArrays.replace_storage(v) do c
        isbitstype(eltype(c)) ? c : convert(PooledArrays.PooledArray, c)
    end
    @test eltype(v) == eltype(v_pooled)
    @test all(v.a .== v_pooled.a)
    @test all(v.b .== v_pooled.b)
    @test !isa(v_pooled.a, PooledArrays.PooledArray)
    @test isa(v_pooled.b, PooledArrays.PooledArray)
end

@testset "roweq" begin
    a = ["a", "b", "a", "a"]
    b = PooledArrays.PooledArray(["x", "y", "z", "x"])
    s = StructArray((a, b))
    @test StructArrays.roweq(s, 1, 1)
    @test !StructArrays.roweq(s, 1, 2)
    @test !StructArrays.roweq(s, 1, 3)
    @test StructArrays.roweq(s, 1, 4)
    strs = WeakRefStrings.StringArray(["a", "a", "b"])
    @test StructArrays.roweq(strs, 1, 1)
    @test StructArrays.roweq(strs, 1, 2)
    @test !StructArrays.roweq(strs, 1, 3)
    @test !StructArrays.roweq(strs, 2, 3)
end

@testset "permute" begin
    a = WeakRefStrings.StringVector(["a", "b", "c"])
    b = PooledArrays.PooledArray([1, 2, 3])
    c = [:a, :b, :c]
    s = StructArray(a=a, b=b, c=c)
    permute!(s, [2, 3, 1])
    @test s.a == ["b", "c", "a"]
    @test s.b == [2, 3, 1]
    @test s.c == [:b, :c, :a]
    s = StructArray(a=[1, 2], b=["a", "b"])
    t = StructArray(a=[3, 4], b=["c", "d"])
    copyto!(s, t)
    @test s == t

    s = StructArray(a=[1, 2], b=["a", "b"])
    t = StructArray(a=[3, 4], b=["c", "d"])
    copyto!(s, 1, t, 1, 2)
    @test s == t

    a = WeakRefStrings.StringVector(["a", "b", "c"])
    b = PooledArrays.PooledArray(["1", "2", "3"])
    c = [:a, :b, :c]
    s = StructArray(a=a, b=b, c=c)
    ref = refarray(s)
    Base.permute!!(ref, sortperm(s))
    @test issorted(s)
end

@testset "sortperm" begin
    c = StructArray(a=[1,1,2,2], b=[1,2,3,3], c=["a","b","c","d"])
    d = StructArray(a=[1,1,2,2], b=[1,2,3,3], c=["a","b","c","d"])
    @test issorted(c)
    @test sortperm(c) == [1,2,3,4]
    permute!(c, [2,3,4,1])
    @test c == StructArray(a=[1,2,2,1], b=[2,3,3,1], c=["b","c","d","a"])
    @test sortperm(c) == [4,1,2,3]
    @test !issorted(c)
    @test sort(c) == d
    sort!(c)
    @test c == d

    c = StructArray(a=[1,1,2,2], b=[1,2,3,3], c=PooledArrays.PooledArray(["a","b","c","d"]))
    d = StructArray(a=[1,1,2,2], b=[1,2,3,3], c=PooledArrays.PooledArray(["a","b","c","d"]))
    @test issorted(c)
    @test sortperm(c) == [1,2,3,4]
    permute!(c, [2,3,4,1])
    @test c == StructArray(a=[1,2,2,1], b=[2,3,3,1], c=PooledArrays.PooledArray(["b","c","d","a"]))
    @test sortperm(c) == [4,1,2,3]
    @test !issorted(c)
    @test sort(c) == d
    sort!(c)
    @test c == d
end

@testset "iterators" begin
    c = [1, 2, 3, 1, 1]
    d = StructArrays.GroupPerm(c)
    @test parent(d) == c
    @test eltype(d) == UnitRange{Int}
    @test Base.IteratorEltype(d) == Base.HasEltype()
    @test sortperm(d) == sortperm(c)
    s = collect(d)
    @test s == [1:3, 4:4, 5:5]
    t = collect(StructArrays.finduniquesorted(c))
    @test first.(t) == [1, 2, 3]
    @test last.(t) == [[1, 4, 5], [2], [3]]
    u = collect(StructArrays.uniquesorted(c))
    @test u == [1, 2, 3]
end

@testset "similar" begin
    t = StructArray(a = rand(10), b = rand(Bool, 10))
    s = similar(t)
    @test eltype(s) == NamedTuple{(:a, :b), Tuple{Float64, Bool}}
    @test size(s) == (10,)
    t = StructArray(a = rand(10, 2), b = rand(Bool, 10, 2))
    s = similar(t, 3, 5)
    @test eltype(s) == NamedTuple{(:a, :b), Tuple{Float64, Bool}}
    @test size(s) == (3, 5)
    s = similar(t, (3, 5))
    @test eltype(s) == NamedTuple{(:a, :b), Tuple{Float64, Bool}}
    @test size(s) == (3, 5)
end

@testset "empty" begin
    s = StructVector(a = [1, 2, 3], b = ["a", "b", "c"])
    empty!(s)
    @test isempty(s.a)
    @test isempty(s.b)
end

@testset "constructor from existing array" begin
    v = rand(ComplexF64, 5, 3)
    t = @inferred StructArray(v)
    @test size(t) == (5, 3)
    @test t[2,2] == v[2,2]
    t2 = convert(StructArray, v)::StructArray
    @test t2 == t
    t3 = StructArray(t)::StructArray
    @test t3 == t
    @test convert(StructArray, t) == t

    v = rand(ComplexF64, 5)
    t = @inferred StructVector(v)
    @test t[2] == v[2]
    @test size(t) == (5,)
    @test t == convert(StructVector, v)
    @test t == convert(StructVector, t)
end

@testset "tuple case" begin
    s = StructArray(([1], ["test"],))
    @test s[1] == (1, "test")
    @test Base.getproperty(s, 1) == [1]
    @test Base.getproperty(s, 2) == ["test"]
    t = StructArray{Tuple{Int, Float64}}(([1], [1.2]))
    @test t[1] == (1, 1.2)

    t[1] = (2, 3)
    @test t[1] == (2, 3.0)
    push!(t, (1, 2))
    @test getproperty(t, 1) == [2, 1]
    @test getproperty(t, 2) == [3.0, 2.0]
end

@testset "constructor from slices" begin
    if VERSION >= v"1.1"
        X = [1.0 2.0; 3.0 4.0]
        @test StructArray{Complex{Float64}}(X; dims=1) == [Complex(1.0,3.0), Complex(2.0,4.0)]
        @test StructArray{Complex{Float64}}(X; dims=2) == [Complex(1.0,2.0), Complex(3.0,4.0)]

        X = [1.0 2.0; 3.0 4.0; 5.0 6.0]
        @test StructArray{Tuple{Float64,Complex{Float64}}}(X; dims=1) == [(1.0,Complex(3.0,5.0)), (2.0, Complex(4.0,6.0))]
    end
end


struct A
    x::Int
    y::Int
    A(x) = new(x, x)
end

@testset "internal constructor" begin
    v = A.([1, 2, 3])
    s = StructArray(v)
    @test s[1] == A(1)
    @test s[2] == A(2)
    @test s[3] == A(3)
end

@testset "kwargs constructor" begin
    a = [1.2]
    b = [2.3]
    @test StructArray(a=a, b=b) == StructArray((a=a, b=b))
    @test StructArray{ComplexF64}(re=a, im=b) == StructArray{ComplexF64}((a, b))
    f1() = StructArray(a=[1.2], b=["test"])
    f2() = StructArray{Pair}(first=[1.2], second=["test"])
    t1 = @inferred f1()
    t2 = @inferred f2()
    @test t1 == StructArray((a=[1.2], b=["test"]))
    @test t2 == StructArray{Pair}(([1.2], ["test"]))
end

@testset "complex" begin
    a, b = [1 2; 3 4], [4 5; 6 7]
    t = StructArray{ComplexF64}((a, b))
    @test t[2,2] == ComplexF64(4, 7)
    @test t[2,1:2] == StructArray{ComplexF64}(([3, 4], [6, 7]))
    @test view(t, 2, 1:2) == StructArray{ComplexF64}((view(a, 2, 1:2), view(b, 2, 1:2)))
end

@testset "copy" begin
    a, b = [1 2; 3 4], [4 5; 6 7]
    t = StructArray{ComplexF64}((a, b))
    t2 = @inferred copy(t)
    @test t2[1,1] == 1.0 + im*4.0
    t2[1,1] = 2.0 + im*4.0
    # Test we actually did a copy
    @test t[1,1] == 1.0 + im*4.0
    # Test that `copy` works, even when the array type changes (e.g. views)
    s = rand(10, 2)
    v = StructArray{ComplexF64}((view(s, :, 1), view(s, :, 2)))
    v2 = copy(v)
    @test v2.re isa Vector
    @test v2.im isa Vector
    @test v2.re == copy(v.re)
    @test v2.im == copy(v.im)
end

@testset "undef initializer" begin
    t = @inferred StructArray{ComplexF64}(undef, 5, 5)
    @test eltype(t) == ComplexF64
    @test size(t) == (5,5)
    c = 2 + im
    t[1,1] = c
    @test t[1,1] == c
end

@testset "resize!" begin
    t = StructArray{Pair}(([3, 5], ["a", "b"]))
    resize!(t, 5)
    @test length(t) == 5
    p = 1 => "c"
    t[5] = p
    @test t[5] == p
end

@testset "concat" begin
    t = StructArray{Pair}(([3, 5], ["a", "b"]))
    push!(t, (2 => "c"))
    @test t == StructArray{Pair}(([3, 5, 2], ["a", "b", "c"]))
    append!(t, t)
    @test t == StructArray{Pair}(([3, 5, 2, 3, 5, 2], ["a", "b", "c", "a", "b", "c"]))
    t = StructArray{Pair}(([3, 5], ["a", "b"]))
    t2 = StructArray{Pair}(([1, 6], ["a", "b"]))
    @test cat(t, t2; dims=1)::StructArray == StructArray{Pair}(([3, 5, 1, 6], ["a", "b", "a", "b"])) == vcat(t, t2)
    @test vcat(t, t2) isa StructArray
    @test cat(t, t2; dims=2)::StructArray == StructArray{Pair}(([3 1; 5 6], ["a" "a"; "b" "b"])) == hcat(t, t2)
    @test hcat(t, t2) isa StructArray
end

f_infer() = StructArray{ComplexF64}((rand(2,2), rand(2,2)))
g_infer() = StructArray([(a=(b="1",), c=2)], unwrap = t -> t <: NamedTuple)
tup_infer() = StructArray([(1, 2), (3, 4)])
cols_infer() = StructArray(([1, 2], [1.2, 2.3]))

@testset "inferrability" begin
    @inferred f_infer()
    @inferred g_infer()
    @test g_infer().a.b == ["1"]
    s = @inferred tup_infer()
    @test StructArrays.components(s) == ([1, 3], [2, 4])
    @test s[1] == (1, 2)
    @test s[2] == (3, 4)
    @inferred cols_infer()
end

@testset "propertynames" begin
    a = StructArray{ComplexF64}((Float64[], Float64[]))
    @test sort(collect(propertynames(a))) == [:im, :re]
end

@testset "tables" begin
    s = StructArray([(a=1, b="test")])
    @test Tables.schema(s) == Tables.Schema((:a, :b), (Int, String))
    @test Tables.rows(s)[1].a == 1
    @test Tables.rows(s)[1].b == "test"
    @test Tables.columns(s).a == [1]
    @test Tables.columns(s).b == ["test"]
    @test Tables.istable(s)
    @test Tables.istable(typeof(s))
    @test Tables.rowaccess(s)
    @test Tables.rowaccess(typeof(s))
    @test Tables.columnaccess(s)
    @test Tables.columnaccess(typeof(s))
    @test Tables.getcolumn(Tables.columns(s), 1) == [1]
    @test Tables.getcolumn(Tables.columns(s), :a) == [1]
    @test Tables.getcolumn(Tables.columns(s), 2) == ["test"]
    @test Tables.getcolumn(Tables.columns(s), :b) == ["test"]
    @test append!(StructArray([1im]), [(re = 111, im = 222)]) ==
        StructArray([1im, 111 + 222im])
    @test append!(StructArray([1im]), (x for x in [(re = 111, im = 222)])) ==
        StructArray([1im, 111 + 222im])
    @test append!(StructArray([1im]), Table(re = [111], im = [222])) ==
        StructArray([1im, 111 + 222im])
    # Testing integer column "names":
    @test invoke(append!, Tuple{StructVector,Any}, StructArray(([0],)), StructArray(([1],))) ==
        StructArray(([0, 1],))
end

struct S
    x::Int
    y::Float64
    S(x) = new(x, x)
end

StructArrays.createinstance(::Type{<:S}, x, y) = S(x)

@testset "inner" begin
    v = StructArray{S}(([1], [1]))
    @test v[1] == S(1)
    @test v[1].y isa Float64
end

@testset "arrayof" begin
    v = StructArrays.arrayof(Missing, (2,))
    @test v isa Array{Missing, 1}
    v = StructArrays.arrayof(Int, (2,))
    @test v isa Array{Int, 1}
end

const initializer = StructArrays.ArrayInitializer(t -> t <: Union{Tuple, NamedTuple, Pair})
collect_structarray_rec(t) = collect_structarray(t, initializer = initializer)

@testset "collectnamedtuples" begin
    v = [(a = 1, b = 2), (a = 1, b = 3)]
    @test collect_structarray_rec(v) == StructArray((a = Int[1, 1], b = Int[2, 3]))

    # test inferrability with constant eltype
    itr = [(a = 1, b = 2), (a = 1, b = 2), (a = 1, b = 12)]
    el, st = iterate(itr)
    dest = initializer(typeof(el), (3,))
    dest[1] = el
    @inferred StructArrays.collect_to_structarray!(dest, itr, 2, st)

    v = [(a = 1, b = 2), (a = 1.2, b = 3)]
    @test collect_structarray_rec(v) == StructArray((a = [1, 1.2], b = Int[2, 3]))
    @test typeof(collect_structarray_rec(v)) == typeof(StructArray((a = Real[1, 1.2], b = Int[2, 3])))
    @test StructArray(v[i] for i in eachindex(v)) == StructArray((a = [1, 1.2], b = Int[2, 3]))

    s = StructArray(a = [1, 2], b  = [3, 4])
    @test collect_structarray(LazyRow(s, i) for i in eachindex(s)) == s
    @test collect_structarray_rec(LazyRow(s, i) for i in eachindex(s)) == s

    v = [(a = 1, b = 2), (a = 1.2, b = "3")]
    @test collect_structarray_rec(v) == StructArray((a = [1, 1.2], b = Any[2, "3"]))
    @test typeof(collect_structarray_rec(v)) == typeof(StructArray((a = Real[1, 1.2], b = Any[2, "3"])))

    v = [(a = 1, b = 2), (a = 1.2, b = 2), (a = 1, b = "3")]
    @test collect_structarray_rec(v) == StructArray((a = Real[1, 1.2, 1], b = Any[2, 2, "3"]))
    @test typeof(collect_structarray_rec(v)) == typeof(StructArray((a = Real[1, 1.2, 1], b = Any[2, 2, "3"])))

    # length unknown
    itr = Iterators.filter(isodd, 1:8)
    tuple_itr = ((a = i+1, b = i-1) for i in itr)
    @test collect_structarray_rec(tuple_itr) == StructArray((a = [2, 4, 6, 8], b = [0, 2, 4, 6]))
    tuple_itr_real = (i == 1 ? (a = 1.2, b =i-1) : (a = i+1, b = i-1) for i in itr)
    @test collect_structarray_rec(tuple_itr_real) == StructArray((a = Real[1.2, 4, 6, 8], b = [0, 2, 4, 6]))

    # empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = ((a = i+1, b = i-1) for i in itr)
    @test collect_structarray_rec(tuple_itr) == StructArray((a = Int[], b = Int[]))

    itr = (i for i in 0:-1)
    tuple_itr = ((a = i+1, b = i-1) for i in itr)
    @test collect_structarray_rec(tuple_itr) == StructArray((a = Int[], b = Int[]))
end

@testset "collecttuples" begin
    v = [(1, 2), (1, 3)]
    @test collect_structarray_rec(v) == StructArray((Int[1, 1], Int[2, 3]))
    @inferred collect_structarray_rec(v)

    @test collect_structarray(v) == StructArray((Int[1, 1], Int[2, 3]))
    @inferred collect_structarray(v)

    v = [(1, 2), (1.2, 3)]
    @test collect_structarray_rec(v) == StructArray((Real[1, 1.2], Int[2, 3]))

    v = [(1, 2), (1.2, "3")]
    @test collect_structarray_rec(v) == StructArray((Real[1, 1.2], Any[2, "3"]))
    @test typeof(collect_structarray_rec(v)) == typeof(StructArray((Real[1, 1.2], Any[2, "3"])))

    v = [(1, 2), (1.2, 2), (1, "3")]
    @test collect_structarray_rec(v) == StructArray((Real[1, 1.2, 1], Any[2, 2, "3"]))
    # length unknown
    itr = Iterators.filter(isodd, 1:8)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_structarray_rec(tuple_itr) == StructArray(([2, 4, 6, 8], [0, 2, 4, 6]))
    tuple_itr_real = (i == 1 ? (1.2, i-1) : (i+1, i-1) for i in itr)
    @test collect_structarray_rec(tuple_itr_real) == StructArray((Real[1.2, 4, 6, 8], [0, 2, 4, 6]))
    @test typeof(collect_structarray_rec(tuple_itr_real)) == typeof(StructArray((Real[1.2, 4, 6, 8], [0, 2, 4, 6])))

    # empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_structarray_rec(tuple_itr) == StructArray((Int[], Int[]))

    itr = (i for i in 0:-1)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_structarray_rec(tuple_itr) == StructArray((Int[], Int[]))
end

@testset "collectscalars" begin
    v = (i for i in 1:3)
    @test collect_structarray_rec(v) == [1,2,3]
    @inferred collect_structarray_rec(v)

    v = (i == 1 ? 1.2 : i for i in 1:3)
    @test collect_structarray_rec(v) == collect(v)

    itr = Iterators.filter(isodd, 1:100)
    @test collect_structarray_rec(itr) == collect(itr)
    real_itr = (i == 1 ? 1.5 : i for i in itr)
    @test collect_structarray_rec(real_itr) == collect(real_itr)
    @test eltype(collect_structarray_rec(real_itr)) == Real

    #empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = (exp(i) for i in itr)
    @test collect_structarray_rec(tuple_itr) == Float64[]

    itr = (i for i in 0:-1)
    tuple_itr = (exp(i) for i in itr)
    @test collect_structarray_rec(tuple_itr) == Float64[]

    t = collect_structarray_rec((a = i,) for i in (1, missing, 3))
    @test StructArrays.components(t)[1] isa Array{Union{Int, Missing}}
    @test isequal(StructArrays.components(t)[1], [1, missing, 3])
end

pair_structarray((first, last)) = StructArray{Pair{eltype(first), eltype(last)}}((first, last))

@testset "collectpairs" begin
    v = (i=>i+1 for i in 1:3)
    @test collect_structarray_rec(v) == pair_structarray([1,2,3] => [2,3,4])
    @test eltype(collect_structarray_rec(v)) == Pair{Int, Int}

    v = (i == 1 ? (1.2 => i+1) : (i => i+1) for i in 1:3)
    @test collect_structarray_rec(v) == pair_structarray([1.2,2,3] => [2,3,4])
    @test eltype(collect_structarray_rec(v)) == Pair{Real, Int}

    v = ((a=i,) => (b="a$i",) for i in 1:3)
    @test collect_structarray_rec(v) == pair_structarray(StructArray((a = [1,2,3],)) => StructArray((b = ["a1","a2","a3"],)))
    @test eltype(collect_structarray_rec(v)) == Pair{NamedTuple{(:a,), Tuple{Int64}}, NamedTuple{(:b,), Tuple{String}}}

    v = (i == 1 ? (a="1",) => (b="a$i",) : (a=i,) => (b="a$i",) for i in 1:3)
    @test collect_structarray_rec(v) == pair_structarray(StructArray((a = ["1",2,3],)) => StructArray((b = ["a1","a2","a3"],)))
    @test eltype(collect_structarray_rec(v)) == Pair{NamedTuple{(:a,), Tuple{Any}}, NamedTuple{(:b,), Tuple{String}}}

    # empty
    v = ((a=i,) => (b="a$i",) for i in 0:-1)
    @test collect_structarray_rec(v) == pair_structarray(StructArray((a = Int[],)) => StructArray((b = String[],)))
    @test eltype(collect_structarray_rec(v)) == Pair{NamedTuple{(:a,), Tuple{Int}}, NamedTuple{(:b,), Tuple{String}}}

    v = Iterators.filter(t -> t.first.a == 4, ((a=i,) => (b="a$i",) for i in 1:3))
    @test collect_structarray_rec(v) == pair_structarray(StructArray((a = Int[],)) => StructArray((b = String[],)))
    @test eltype(collect_structarray_rec(v)) == Pair{NamedTuple{(:a,), Tuple{Int}}, NamedTuple{(:b,), Tuple{String}}}

    t = collect_structarray_rec((b = 1,) => (a = i,) for i in (2, missing, 3))
    s = pair_structarray(StructArray(b = [1,1,1]) => StructArray(a = [2, missing, 3]))
    @test s[1] == t[1]
    @test ismissing(t[2].second.a)
    @test s[3] == t[3]
end

@testset "collect2D" begin
    s = (l for l in [(a=i, b=j) for i in 1:3, j in 1:4])
    v = collect_structarray(s)
    @test size(v) == (3, 4)
    @test v.a == [i for i in 1:3, j in 1:4]
    @test v.b == [j for i in 1:3, j in 1:4]
end

@testset "collectoffset" begin
    s = OffsetArray([(a=1,) for i in 1:10], -3)
    sa = StructArray(s)
    @test sa isa StructArray
    @test axes(sa) == (-2:7,)
    @test sa.a == fill(1, -2:7)

    sa = StructArray(i for i in s)
    @test sa isa StructArray
    @test axes(sa) == (-2:7,)
    @test sa.a == fill(1, -2:7)

    zero_origin(T, d) = OffsetArray{T}(undef, map(r -> r .- 1, d))
    sa = collect_structarray(
        [(a = 1,), (a = 2,), (a = 3,)],
        initializer = StructArrays.StructArrayInitializer(t -> false, zero_origin),
    )
    @test sa isa StructArray
    @test collect(sa.a) == 1:3
    @test sa.a isa OffsetArray

    sa = collect_structarray(
        (x for x in [(a = 1,), (a = 2,), (a = 3,)] if true),
        initializer = StructArrays.StructArrayInitializer(t -> false, zero_origin),
    )
    @test sa isa StructArray
    @test collect(sa.a) == 1:3
    @test sa.a isa OffsetArray
end

@testset "collectstructarrays" begin
    s = StructArray(a = rand(10), b = rand(10))
    t = StructArray(a = rand(10), b = rand(10))
    v = StructArray([s, t])
    @test v.a[1] == s.a
    @test v.a[2] == t.a
    @test v.b[1] == s.b
    @test v.b[2] == t.b
    @test v[1] == s
    @test v[2] == t

    s = LazyRows(StructArray(a = rand(10), b = rand(10)))
    t = LazyRows(StructArray(a = rand(10), b = rand(10)))
    v = StructArray([s, t])
    @test v.a[1] == s.a
    @test v.a[2] == t.a
    @test v.b[1] == s.b
    @test v.b[2] == t.b
    @test v[1] == s
    @test v[2] == t
end

@testset "hasfields" begin
    @test StructArrays.hasfields(ComplexF64)
    @test !StructArrays.hasfields(Any)
    @test StructArrays.hasfields(Tuple{Union{Int, Missing}})
    @test StructArrays.hasfields(typeof((a=1,)))
    @test !StructArrays.hasfields(NamedTuple)
    @test !StructArrays.hasfields(Tuple{Int, Vararg{Int, N}} where {N})
    @test StructArrays.hasfields(Missing)
    @test !StructArrays.hasfields(Union{Tuple{Int}, Missing})
    @test StructArrays.hasfields(Nothing)
    @test !StructArrays.hasfields(Union{Tuple{Int}, Nothing})
end

@testset "reshape" begin
    s = StructArray(a=[1,2,3,4], b=["a","b","c","d"])
    rs = reshape(s, (2, 2))
    @test rs.a == [1 3; 2 4]
    @test rs.b == ["a" "c"; "b" "d"]
end

@testset "lazy" begin
    s = StructArray{ComplexF64}((rand(10, 10), view(rand(100, 100), 1:10, 1:10)))
    rows = LazyRows(s)
    @test propertynames(rows) == (:re, :im)
    @test propertynames(rows[1]) == (:re, :im)
    @test staticschema(eltype(rows)) == staticschema(ComplexF64)
    @test getproperty(rows, 1) isa Matrix{Float64}
    @test getproperty(rows, :re) isa Matrix{Float64}
    @test IndexStyle(rows) isa IndexCartesian
    @test IndexStyle(typeof(rows)) isa IndexCartesian
    @test all(t -> t.re >= 0, s)
    @test all(t -> t.re >= 0, rows)
    rows[13].re = -12
    rows[13].im = 0

    s = StructArray(rand(ComplexF64, 10, 10))
    rows = LazyRows(s)
    @test propertynames(rows) == (:re, :im)
    @test propertynames(rows[1]) == (:re, :im)
    @test staticschema(eltype(rows)) == staticschema(ComplexF64)
    @test getproperty(rows, 1) isa Matrix{Float64}
    @test getproperty(rows, :re) isa Matrix{Float64}
    @test IndexStyle(rows) isa IndexLinear
    @test IndexStyle(typeof(rows)) isa IndexLinear
    @test all(t -> t.re >= 0, s)
    @test all(t -> t.re >= 0, rows)
    rows[13].re = -12
    rows[13].im = 0
    @test !all(t -> t.re >= 0, s)
    @test !all(t -> t.re >= 0, rows)

    @test !all(t -> t.re >= 0, s)
    @test !all(t -> t.re >= 0, rows)
    io = IOBuffer()
    show(io, rows[13])
    str = String(take!(io))
    @test str == "LazyRow(re = -12.0, im = 0.0)"

    io = IOBuffer()
    Base.showarg(io, rows, true)
    str = String(take!(io))
    if VERSION < v"1.6-"
        @test str == "LazyRows(::Array{Float64,2}, ::Array{Float64,2}) with eltype LazyRow{Complex{Float64}}"
    else
        @test str == "LazyRows(::Matrix{Float64}, ::Matrix{Float64}) with eltype LazyRow{ComplexF64}"
    end
    io = IOBuffer()
    Base.showarg(io, rows, false)
    str = String(take!(io))
    if VERSION < v"1.6-"
        @test str == "LazyRows(::Array{Float64,2}, ::Array{Float64,2})"
    else
        @test str == "LazyRows(::Matrix{Float64}, ::Matrix{Float64})"
    end
    s = StructArray((rand(10, 10), rand(10, 10)))
    rows = LazyRows(s)
    @test IndexStyle(rows) isa IndexLinear
    @test IndexStyle(typeof(rows)) isa IndexLinear
    @test all(t -> Tables.getcolumn(t, 1) >= 0, s)
    @test all(t -> getproperty(t, 1) >= 0, rows)
    setproperty!(rows[13], 1, -12)
    setproperty!(rows[13], 2, 0)
    @test !all(t -> Tables.getcolumn(t, 1) >= 0, s)
    @test !all(t -> getproperty(t, 1) >= 0, rows)

    io = IOBuffer()
    show(io, rows[13])
    str = String(take!(io))
    @test str == "LazyRow(-12.0, 0.0)"

    io = IOBuffer()
    Base.showarg(io, rows, true)
    str = String(take!(io))
    if VERSION < v"1.6-"
        @test str == "LazyRows(::Array{Float64,2}, ::Array{Float64,2}) with eltype LazyRow{Tuple{Float64,Float64}}"
    else
        @test str == "LazyRows(::Matrix{Float64}, ::Matrix{Float64}) with eltype LazyRow{Tuple{Float64, Float64}}"
    end
    io = IOBuffer()
    Base.showarg(io, rows, false)
    str = String(take!(io))
    if VERSION < v"1.6-"
        @test str == "LazyRows(::Array{Float64,2}, ::Array{Float64,2})"
    else
        @test str == "LazyRows(::Matrix{Float64}, ::Matrix{Float64})"
    end
end

@testset "refarray" begin
    s = PooledArrays.PooledArray(["a", "b", "c", "c"])
    @test refarray(s) == UInt8.([1, 2, 3, 3])

    s = WeakRefStrings.StringArray(["a", "b"])
    @test refarray(s) isa WeakRefStrings.StringArray{WeakRefStrings.WeakRefString{UInt8}}
    @test all(isequal.(s, refarray(s)))
    s = WeakRefStrings.StringArray(["a", missing])
    @test refarray(s) isa WeakRefStrings.StringArray{Union{WeakRefStrings.WeakRefString{UInt8}, Missing}}
    @test all(isequal.(s, refarray(s)))
    a = WeakRefStrings.StringVector(["a", "b", "c"])
    b = PooledArrays.PooledArray(["1", "2", "3"])
    c = [:a, :b, :c]
    s = StructArray(a=a, b=b, c=c)
    ref = refarray(s)
    @test ref[1].a isa WeakRefStrings.WeakRefString{UInt8}
    @test ref[1].b isa Integer
    for i in 1:3
        @test refvalue(s, ref[i]) == s[i]
    end
end

@testset "show" begin
    s = StructArray(Complex{Int64}[1+im, 2-im])
    io = IOBuffer()
    Base.showarg(io, s, true)
    str = String(take!(io))
    if VERSION < v"1.6-"
        @test str == "StructArray(::Array{Int64,1}, ::Array{Int64,1}) with eltype Complex{Int64}"
    else
        @test str == "StructArray(::Vector{Int64}, ::Vector{Int64}) with eltype Complex{Int64}"
    end
    io = IOBuffer()
    Base.showarg(io, s, false)
    str = String(take!(io))
    if VERSION < v"1.6-"
        @test str == "StructArray(::Array{Int64,1}, ::Array{Int64,1})"
    else
        @test str == "StructArray(::Vector{Int64}, ::Vector{Int64})"
    end
end

@testset "append!!" begin
    dest_examples = [
        ("mutate", StructVector(a = [1], b = [2])),
        ("widen", StructVector(a = [1], b = [nothing])),
    ]
    itr = [(a = 1, b = 2), (a = 1, b = 2), (a = 1, b = 12)]
    itr_examples = [
        ("HasLength", () -> itr),
        ("StructArray", () -> StructArray(itr)),
        ("SizeUnknown", () -> (x for x in itr if isodd(x.a))),
        # Broken due to https://github.com/JuliaArrays/StructArrays.jl/issues/100:
        # ("empty", (x for x in itr if false)),
        ("stateful", () -> Iterators.Stateful(itr)),
    ]
    @testset "$destlabel $itrlabel" for (destlabel, dest) in dest_examples,
                                        (itrlabel, makeitr) in itr_examples

        @test vcat(dest, StructVector(makeitr())) == append!!(copy(dest), makeitr())
    end
end

struct ArrayConverter end

Adapt.adapt_storage(::ArrayConverter, xs::AbstractArray) = convert(Array, xs)

@testset "adapt" begin
    s = StructArray(a = 1:10, b = StructArray(c = 1:10, d = 1:10))
    t = adapt(ArrayConverter(), s)
    @test propertynames(t) == (:a, :b)
    @test s == t
    @test t.a isa Array
    @test t.b.c isa Array
    @test t.b.d isa Array
end

struct MyArray{T,N} <: AbstractArray{T,N}
    A::Array{T,N}
end
MyArray{T}(::UndefInitializer, sz::Dims) where T = MyArray(Array{T}(undef, sz))
Base.IndexStyle(::Type{<:MyArray}) = IndexLinear()
Base.getindex(A::MyArray, i::Int) = A.A[i]
Base.setindex!(A::MyArray, val, i::Int) = A.A[i] = val
Base.size(A::MyArray) = Base.size(A.A)
Base.BroadcastStyle(::Type{<:MyArray}) = Broadcast.ArrayStyle{MyArray}()
Base.similar(bc::Broadcast.Broadcasted{Broadcast.ArrayStyle{MyArray}}, ::Type{ElType}) where ElType =
    MyArray{ElType}(undef, size(bc))

@testset "broadcast" begin
    s = StructArray{ComplexF64}((rand(2,2), rand(2,2)))
    @test isa(@inferred(s .+ s), StructArray)
    @test (s .+ s).re == 2*s.re
    @test (s .+ s).im == 2*s.im
    @test isa(@inferred(broadcast(t->1, s)), Array)
    @test all(x->x==1, broadcast(t->1, s))
    @test isa(@inferred(s .+ 1), StructArray)
    @test s .+ 1 == StructArray{ComplexF64}((s.re .+ 1, s.im))
    r = rand(2,2)
    @test isa(@inferred(s .+ r), StructArray)
    @test s .+ r == StructArray{ComplexF64}((s.re .+ r, s.im))

    s = StructArray{ComplexF64}((MyArray(rand(2,2)), MyArray(rand(2,2))))
    @test_throws MethodError s .+ s
end
