"""
Checks the availability of Overpass servers by sending a request to https://overpass-api.de/api/status.
"""
function check_overpass_server_availability()
    response = String(HTTP.get(OSM_URLS[:overpass_status]).body)
    if occursin("slots available now", response)
        @info "Overpass server is available for download"
    else
        throw(ErrorException("Overpass server is NOT available for download, please wait and try again"))
    end
end

"""
    nominatim_request(query::Dict)::String

Sends a GET request to the Nomatim API: https://nominatim.openstreetmap.org/search.

# Arguments
- `query::Dict`: HTTP GET request query aguments.

# Return
- `String`: Response body as string.
"""
function nominatim_request(query::Dict)::String
    return String(HTTP.get(OSM_URLS[:nominatim_search], query=query).body)
end

"""
    nominatim_request(data::Dict)::String

Sends a POST request to the Overpass API: http://overpass-api.de/api/interpreter.

# Arguments
- `data::String`: HTTP POST data.

# Return
- `String`: Response body as string.
"""
function overpass_request(data::String)::String
    check_overpass_server_availability()
    return String(HTTP.post(OSM_URLS[:overpass_map], body=data).body)
end

"""
    nominatim_polygon_query(place_name::String)::Dict{String,Any}

Forms query arguments required for a Nomatim search at https://nominatim.openstreetmap.org/search.

# Arguments
- `place_name::String`: Place name string used in request to the nominatim api.

# Return
- `Dict{String,Any}`: GET request query arguments.
"""
function nominatim_polygon_query(place_name::String)::Dict{String,Any}
    return Dict(
        "format" => "json",
        "limit" => 5,
        "dedupe" => 0,
        "polygon_geojson" => 1,
        "q" => place_name
    )
end

"""
    overpass_query(filters::String,
                   metadata::Bool=false,
                   download_format::Symbol=:osm,
                   bbox::Union{Vector{AbstractFloat},Nothing}=nothing
                   )::String

Forms an Overpass query string. For a guide on the OSM query language, see https://wiki.openstreetmap.org/wiki/Overpass_API/Language_Guide.

# Arguments
- `filters::String`: Filters for the query, e.g. polygon filter, highways only, traffic lights only, etc.
- `metadata::Bool=false`: Set true to return metadata.
- `download_format::Symbol=:osm`: Download format, either `:osm`, `:xml` or `json`.
- `bbox::Union{Vector{AbstractFloat},Nothing}=nothing`: Optional bounding box filter.

# Return
- `String`: Overpass query string.
"""
function overpass_query(filters::String,
                        metadata::Bool=false,
                        download_format::Symbol=:osm,
                        bbox::Union{Vector{<:AbstractFloat},Nothing}=nothing
                        )::String
    download_format_str = """[out:$(OSM_DOWNLOAD_FORMAT[download_format])]"""
    bbox_str = bbox === nothing ? "" : """[bbox:$(replace("$bbox", r"[\[ \]]" =>  ""))]"""
    metadata_str = metadata ? "meta" : ""
    query = """$download_format_str[timeout:180]$bbox_str;($filters);out count;out $metadata_str;"""
    @debug """Making overpass query: $query"""
    return query
end

"""
    overpass_polygon_network_query(geojson_polygons::Vector{Vector{Any}},
                                   network_type::Symbol=:drive,
                                   metadata::Bool=false,
                                   download_format::Symbol=:osm
                                   )::String

Forms an Overpass query string using geojosn polygon coordinates as a filter.

# Arguments
- `geojson_polygons::Vector{Vector{Any}}`: Vector of `[lat, lon, ...]` polygon coordinates.
- `network_type::Symbol=:drive`: Network type filter, pick from `:drive`, `:drive_service`, `:walk`, `:bike`, `:all`, `:all_private`, `:none`, `:rail`.
- `metadata::Bool=false`: Set true to return metadata.
- `download_format::Symbol=:osm`: Download format, either `:osm`, `:xml` or `json`.

# Return
- `String`: Overpass query string.
"""
function overpass_polygon_network_query(geojson_polygons::AbstractVector{<:AbstractVector},
                                        network_type::Symbol=:drive,
                                        metadata::Bool=false,
                                        download_format::Symbol=:osm
                                        )::String
    way_filter = WAY_FILTERS_QUERY[network_type]
    relation_filter = RELATION_FILTERS_QUERY[network_type]

    filters = ""
    for polygon in geojson_polygons
        polygon = map(x -> [x[2], x[1]], polygon) # switch lon-lat to lat-lon
        polygon_str = replace("$polygon", r"[\[,\]]" =>  "")
        filters *= """way$way_filter(poly:"$polygon_str");>;"""
        if !isnothing(relation_filter)
            filters *= """rel$relation_filter(poly:"$polygon_str");>;"""
        end
    end

    return overpass_query(filters, metadata, download_format)
end

"""
    polygon_from_place_name(place_name::String)::Vector{Vector{Any}}

Retrieves polygon coordinates using any place name string.

# Arguments
- `place_name::String`: Any place name string used as a search argument to the Nominatim API.

# Return
- `Vector{Vector{Any}}`: GeoJSON polygon coordiantes.
"""
function polygon_from_place_name(place_name::String)::Vector{Vector{Any}}
    query = nominatim_polygon_query(place_name)
    response = JSON.parse(nominatim_request(query))

    for item in response
        if item["geojson"]["type"] == "Polygon"
            @info "Using Polygon for $(item["display_name"])"
            return item["geojson"]["coordinates"]
        elseif item["geojson"]["type"] ==  "MultiPolygon"
            @info "Using MultiPolygon for $(item["display_name"])"
            return collect(Iterators.flatten(item["geojson"]["coordinates"]))
        end
    end

    throw(ErrorException("Could not find valid polygon for $place_name"))
end

"""
    osm_network_from_place_name(;place_name::String,
                                network_type::Symbol=:drive,
                                metadata::Bool=false,
                                download_format::Symbol=:osm
                                )::String

Downloads an OpenStreetMap network using any place name string.

# Arguments
- `place_name::String`: Any place name string used as a search argument to the Nominatim API.
- `network_type::Symbol=:drive`: Network type filter, pick from `:drive`, `:drive_service`, `:walk`, `:bike`, `:all`, `:all_private`, `:none`, `:rail`.
- `metadata::Bool=false`: Set true to return metadata.
- `download_format::Symbol=:osm`: Download format, either `:osm`, `:xml` or `json`.

# Return
- `String`: OpenStreetMap network data response string.
"""
function osm_network_from_place_name(;place_name::String,
                                     network_type::Symbol=:drive,
                                     metadata::Bool=false,
                                     download_format::Symbol=:osm
                                     )::String
    geojson_polygons = polygon_from_place_name(place_name)
    query = overpass_polygon_network_query(geojson_polygons, network_type, metadata, download_format)
    return overpass_request(query)
end

"""
    osm_network_from_polygon(;polygon::AbstractVector,
                             network_type::Symbol=:drive,
                             metadata::Bool=false,
                             download_format::Symbol=:osm
                             )::String

Downloads an OpenStreetMap network using a polygon.

# Arguments
- `polygon::AbstractVector`: Vector of longitude-latitude pairs.
- `network_type::Symbol=:drive`: Network type filter, pick from `:drive`, `:drive_service`, `:walk`, `:bike`, `:all`, `:all_private`, `:none`, `:rail`.
- `metadata::Bool=false`: Set true to return metadata.
- `download_format::Symbol=:osm`: Download format, either `:osm`, `:xml` or `json`.

# Return
- `String`: OpenStreetMap network data response string.
"""
function osm_network_from_polygon(;polygon::AbstractVector{<:AbstractVector{<:Real}},
                                  network_type::Symbol=:drive,
                                  metadata::Bool=false,
                                  download_format::Symbol=:osm
                                  )::String
    query = overpass_polygon_network_query([polygon], network_type, metadata, download_format)
    return overpass_request(query)
end

"""
    overpass_bbox_network_query(bbox::Vector{AbstractFloat},
                                network_type::Symbol=:drive,
                                metadata::Bool=false,
                                download_format::Symbol=:osm
                                )::String

Forms an Overpass query string using a bounding box as a filter.

# Arguments
- `bbox::Vector{AbstractFloat}`: Vector of bounding box coordinates `[minlat, minlon, maxlat, maxlon]`.
- `network_type::Symbol=:drive`: Network type filter, pick from `:drive`, `:drive_service`, `:walk`, `:bike`, `:all`, `:all_private`, `:none`, `:rail`.
- `metadata::Bool=false`: Set true to return metadata.
- `download_format::Symbol=:osm`: Download format, either `:osm`, `:xml` or `json`.

# Return
- `String`: Overpass query string.
"""
function overpass_bbox_network_query(bbox::Vector{<:AbstractFloat},
                                     network_type::Symbol=:drive,
                                     metadata::Bool=false,
                                     download_format::Symbol=:osm
                                     )::String
    way_filter = WAY_FILTERS_QUERY[network_type]
    relation_filter = RELATION_FILTERS_QUERY[network_type]
    filters = "way$way_filter;>;"
    if !isnothing(relation_filter)
        filters *= """rel$relation_filter(poly:"$polygon_str");>;"""
    end
    return overpass_query(filters, metadata, download_format, bbox)
end

"""
    osm_network_from_bbox(;minlat::AbstractFloat,
                          minlon::AbstractFloat,
                          maxlat::AbstractFloat,
                          maxlon::AbstractFloat,
                          network_type::Symbol=:drive,
                          metadata::Bool=false,
                          download_format::Symbol=:osm
                          )::String

Downloads an OpenStreetMap network using bounding box coordinates.

# Arguments
- `minlat::AbstractFloat`: Bottom left bounding box latitude coordinate.
- `minlon::AbstractFloat`: Bottom left bounding box longitude coordinate.
- `maxlat::AbstractFloat`: Top right bounding box latitude coordinate.
- `maxlon::AbstractFloat`: Top right bounding box longitude coordinate.
- `network_type::Symbol=:drive`: Network type filter, pick from `:drive`, `:drive_service`, `:walk`, `:bike`, `:all`, `:all_private`, `:none`, `:rail`.
- `metadata::Bool=false`: Set true to return metadata.
- `download_format::Symbol=:osm`: Download format, either `:osm`, `:xml` or `json`.

# Return
- `String`: OpenStreetMap network data response string.
"""
function osm_network_from_bbox(;minlat::AbstractFloat,
                               minlon::AbstractFloat,
                               maxlat::AbstractFloat,
                               maxlon::AbstractFloat,
                               network_type::Symbol=:drive,
                               metadata::Bool=false,
                               download_format::Symbol=:osm
                               )::String
    query = overpass_bbox_network_query([minlat, minlon, maxlat, maxlon], network_type, metadata, download_format)
    return overpass_request(query)
end

"""
    osm_network_from_point(;point::GeoLocation,
                           radius::Number,
                           network_type::Symbol=:drive,
                           metadata::Bool=false,
                           download_format::Symbol=:osm
                           )::String

Downloads an OpenStreetMap network using bounding box coordinates calculated from a centroid point and radius (km).

# Arguments
- `point::GeoLocation`: Centroid point to draw the bounding box around.
- `radius::Number`: Distance (km) from centroid point to each bounding box corner.
- `network_type::Symbol=:drive`: Network type filter, pick from `:drive`, `:drive_service`, `:walk`, `:bike`, `:all`, `:all_private`, `:none`, `:rail`.
- `metadata::Bool=false`: Set true to return metadata.
- `download_format::Symbol=:osm`: Download format, either `:osm`, `:xml` or `json`.

# Return
- `String`: OpenStreetMap network data response string.
"""
function osm_network_from_point(;point::GeoLocation,
                                radius::Number,
                                network_type::Symbol=:drive,
                                metadata::Bool=false,
                                download_format::Symbol=:osm
                                )::String
    bbox = bounding_box_from_point(point, radius)
    return osm_network_from_bbox(;bbox..., network_type=network_type, metadata=metadata, download_format=download_format)
end

"""
Factory method for retrieving download functions.
"""
function osm_network_downloader(download_method::Symbol)::Function
    if download_method == :place_name
        return osm_network_from_place_name
    elseif download_method == :bbox
        return osm_network_from_bbox
    elseif download_method == :point
        return osm_network_from_point
    elseif download_method == :polygon
        return osm_network_from_polygon
    else
        throw(ArgumentError("OSM network downloader $download_method does not exist"))
    end
end

"""
    download_osm_network(download_method::Symbol;
                         network_type::Symbol=:drive,
                         metadata::Bool=false,
                         download_format::Symbol=:osm,
                         save_to_file_location::Union{String,Nothing}=nothing,
                         download_kwargs...
                         )::Union{XMLDocument,Dict{String,Any}}

Downloads an OpenStreetMap network by querying with a place name, bounding box, or centroid point.

# Arguments
- `download_method::Symbol`: Download method, choose from `:place_name`, `:bounding_box` or `:point`.
- `network_type::Symbol=:drive`: Network type filter, pick from `:drive`, `:drive_service`, `:walk`, `:bike`, `:all`, `:all_private`, `:none`, `:rail`
- `metadata::Bool=false`: Set true to return metadata.
- `download_format::Symbol=:osm`: Download format, either `:osm`, `:xml` or `json`.
- `save_to_file_location::Union{String,Nothing}=nothing`: Specify a file location to save downloaded data to disk.

# Required kwargs each Download Method

*`download_method=:place_name`*
- `place_name::String`: Any place name string used as a search argument to the Nominatim API.

*`download_method=:bounding_box`*
- `minlat::AbstractFloat`: Bottom left bounding box latitude coordinate.
- `minlon::AbstractFloat`: Bottom left bounding box longitude coordinate.
- `maxlat::AbstractFloat`: Top right bounding box latitude coordinate.
- `maxlon::AbstractFloat`: Top right bounding box longitude coordinate.

*`download_method=:point`*
- `point::GeoLocation`: Centroid point to draw the bounding box around.
- `radius::Number`: Distance (km) from centroid point to each bounding box corner.

*`download_method=:polygon`*
- `polygon::AbstractVector`: Vector of longitude-latitude pairs.

# Network Types
- `:drive`: Motorways excluding private and service ways.
- `:drive_service`: Motorways including private and service ways.
- `:walk`: Walkways only.
- `:bike`: Cycleways only.
- `:all`: All motorways, walkways and cycleways excluding private ways.
- `:all_private`: All motorways, walkways and cycleways including private ways.
- `:none`: No network filters.
- `:rail`: Railways excluding proposed and platform.

# Return
- `Union{XMLDocument,Dict{String,Any}}`: OpenStreetMap network data parsed as either XML or Dictionary object depending on the download method.
"""
function download_osm_network(download_method::Symbol;
                              network_type::Symbol=:drive,
                              metadata::Bool=false,
                              download_format::Symbol=:osm,
                              save_to_file_location::Union{String,Nothing}=nothing,
                              download_kwargs...
                              )::Union{XMLDocument,Dict{String,Any}}
    downloader = osm_network_downloader(download_method)
    data = downloader(network_type=network_type, metadata=metadata, download_format=download_format; download_kwargs...)
    @info "Downloaded osm network data from $(["$k: $v" for (k, v) in download_kwargs]) in $download_format format"

    if !(save_to_file_location isa Nothing)
        file_extension = "." * String(download_format)

        if !occursin(file_extension, save_to_file_location)
            save_to_file_location *= file_extension
        end

        open(save_to_file_location, "w") do io
            write(io, data)
        end

        @info "Saved osm network data to disk: $save_to_file_location"
    end

    deserializer = string_deserializer(download_format)

    return deserializer(data)
end
