@testset "Downloader selection" begin
    @test LightOSM.osm_network_downloader(:place_name) == LightOSM.osm_network_from_place_name
    @test LightOSM.osm_network_downloader(:bbox) == LightOSM.osm_network_from_bbox
    @test LightOSM.osm_network_downloader(:point) == LightOSM.osm_network_from_point
    @test LightOSM.osm_network_downloader(:polygon) == LightOSM.osm_network_from_polygon
    @test_throws ArgumentError LightOSM.osm_network_downloader(:doesnt_exist)
end