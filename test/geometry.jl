a = GeoLocation(-33.8308, 151.223, 0.0)
A = [GeoLocation(-33.8308, 151.223, 0.0), GeoLocation(-33.8293, 151.221, 0.0)]
b = GeoLocation(-33.8294, 151.22, 0.0)
B = [GeoLocation(-33.8294, 151.22, 0.0), GeoLocation(-33.8301, 151.22, 0.0)]

@testset "Distance tests" begin
    @test abs(LightOSM.euclidean(a, b) - 0.318) < 0.01
    @test sum(abs.(LightOSM.euclidean(A, B) - [0.318, 0.128])) < 0.1
    @test abs(LightOSM.haversine(a, b) - 0.318) < 0.01
    @test sum(abs.(LightOSM.haversine(A, B) - [0.318, 0.128])) < 0.1

    @test abs(distance(a, b, :haversine) - 0.318) < 0.01
    @test abs(distance(a, b, :euclidean) - 0.318) < 0.01
    @test sum(abs.(distance(A, B, :haversine) - [0.318, 0.128])) < 0.01
    @test sum(abs.(distance(A, B, :euclidean) - [0.318, 0.128])) < 0.01
end

@testset "Heading tests" begin
    # Used http://instantglobe.com/CRANES/GeoCoordTool.html to manually calculate headings and distance
    # Note: heading function returns bearings in range of [-180, 180], to convert to [0, 360] scale we need to adjust by (θ + 360) % 360
    @test abs((heading(a, b, :degrees) + 360) % 360 - 299.32559505087795) < 0.01
    @test sum((abs.(heading(A, B, :degrees) .+ 360) .% 360 - [299.32559505087795, 226.07812206538435])) < 0.01
end