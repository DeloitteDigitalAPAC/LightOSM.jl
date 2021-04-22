using JSON
using LightOSM
using LightXML
using Test

@testset "LightOSM Tests" begin
    @testset "utilities.jl" begin include("utilities.jl") end
    @testset "geometry.jl" begin include("geometry.jl") end
    @testset "download.jl" begin include("download.jl") end
end

