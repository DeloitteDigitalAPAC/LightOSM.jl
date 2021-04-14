"""
Determine road maxspeeds given osm way tags dictionary.
"""
function maxspeed(tags::AbstractDict)::Integer
    maxspeed = get(tags, "maxspeed", "default")
    U = DEFAULT_DATA_TYPES[:OSM_MAXSPEED]

    if maxspeed != "default"
        if maxspeed isa Integer
            return maxspeed
        elseif maxspeed isa AbstractFloat
            return U(round(maxspeed))
        elseif maxspeed isa String 
            if occursin("conditional", maxspeed) 
                maxspeed = remove_sub_string_after(maxspeed, "conditional")
            end

            maxspeed = split(maxspeed, COMMON_OSM_STRING_DELIMITERS)

            cleaned_maxspeeds = []
            for speed in maxspeed
                speed = occursin("mph", speed) ? remove_non_numeric(speed) * KMH_PER_MPH : remove_non_numeric(speed)
                push!(cleaned_maxspeeds, speed)
            end
            
            return U(round(mean(cleaned_maxspeeds)))
        else
            throw(ErrorException("Maxspeed is neither a string nor number, check data quality: $maxspeed"))
        end
    else
        highway_type = get(tags, "highway", "other")
        key = getkey(DEFAULT_MAXSPEEDS, highway_type, "other")
        return U(DEFAULT_MAXSPEEDS[key])
    end
end

"""
Determine number of lanes given osm way tags dictionary.
"""
function lanes(tags::AbstractDict)::Integer
    lanes = get(tags, "lanes", "default")
    U = DEFAULT_DATA_TYPES[:OSM_LANES]

    if lanes != "default"
        if lanes isa Integer
            return lanes
        elseif lanes isa AbstractFloat
            return U(round(lanes))
        elseif lanes isa String 
            lanes = split(lanes, COMMON_OSM_STRING_DELIMITERS)
            lanes = [remove_non_numeric(l) for l in lanes]
            return U(round(mean(lanes)))
        else
            throw(ErrorException("Lanes is neither a string nor number, check data quality: $lanes"))
        end
    else
        highway_type = get(tags, "highway", "other")
        key = getkey(DEFAULT_LANES, highway_type, "other")
        return U(DEFAULT_LANES[key])
    end
end


"""
Determind if way is a roundabout given osm way tags dictionary.
"""
is_roundabout(tags::AbstractDict)::Bool = get(tags, "junction", "") == "roundabout" ? true : false

"""
Determine oneway road attribute given osm way tags dictionary.
"""
function is_oneway(tags::AbstractDict)::Bool
    oneway = get(tags, "oneway", "")

    if oneway in ONEWAY_FALSE
        return false
    elseif oneway in ONEWAY_TRUE
        return true
    elseif is_roundabout(tags)
        return true
    else
        highway_type = get(tags, "highway", "other")
        key = getkey(DEFAULT_ONEWAY, highway_type, "other")
        return DEFAULT_ONEWAY[key]
    end
end

"""
Determine reverseway road attribute given osm way tags dictionary.
"""
is_reverseway(tags::AbstractDict)::Bool = get(tags, "oneway", "") in Set(["-1", -1]) ? true : false

"""
Determine if way is of highway type given osm way tags dictionary.
"""
is_highway(tags::AbstractDict)::Bool = haskey(tags, "highway") ? true : false

"""
Determine if way is of railway type given osm way tags dictionary.
"""
is_railway(tags::AbstractDict)::Bool = haskey(tags, "railway") ? true : false

"""
Determine if way matches the specified network type.
"""
function matches_network_type(tags::AbstractDict, network_type::Symbol)::Bool
    for (k, v) in WAY_EXCLUSION_FILTERS[network_type]
        if haskey(tags, k)
            if tags[k] in Set(v)
                return false
            end
        end
    end
    return true
end

"""
Determine if relation is a restriction.
"""
is_restriction(tags::AbstractDict)::Bool = get(tags, "type", "") == "restriction" && haskey(tags, "restriction") ? true : false

"""
Determine if a restriction is valid and has usable data.
"""
function is_valid_restriction(members::AbstractArray, highways::AbstractDict{T,Way{T}})::Bool where T <: Integer
    role_counts = DefaultDict(0)
    role_type_counts = DefaultDict(0)
    ways_set = Set{Integer}()
    ways_mapping = DefaultDict(Vector)
    via_node = nothing

    for member in members
        id = member["ref"]
        type = member["type"]
        role = member["role"]

        if type == "way"
            if !haskey(highways, id) || id in ways_set
                # Cannot process missing and duplicate from/via/to ways
                return false
            else
                push!(ways_set, id)
                push!(ways_mapping[role], id)
            end

        elseif type == "node"
            via_node = id
        end

        role_counts[role] += 1
        role_type_counts["$(role)_$(type)"] += 1
    end

    if !(role_counts["from"] == 1) ||
       !(role_counts["to"] == 1) ||
       !(
           (role_type_counts["via_node"] == 1 && role_type_counts["via_way"] < 1) ||
           (role_type_counts["via_node"] < 1 && role_type_counts["via_way"] >= 1)
        )
        # Restrictions with multiple "from" and "to" members cannot be processed
        # Restrictions with multiple "via" "node" members cannot be processed
        # Restrictions with combination of "via" "node" and "via" "way" members cannot be processed
        return false
    end

    to_way = ways_mapping["to"][1]
    trailing_to_way_nodes = trailing_elements(highways[to_way].nodes)
    from_way = ways_mapping["from"][1]
    trailing_from_way_nodes = trailing_elements(highways[from_way].nodes)

    if via_node isa Integer && (!(via_node in trailing_to_way_nodes) || !(via_node in trailing_from_way_nodes))
        # Via node must be a trailing node on to_way and from_way
        return false
    end

    if haskey(ways_mapping, "via")
        try
            # Via way trailing nodes must intersect with all to_ways and from_ways
            via_ways = ways_mapping["via"]
            via_way_nodes_list = [highways[w].nodes for w in via_ways]
            via_way_nodes = join_arrays_on_common_trailing_elements(via_way_nodes_list...)
            trailing_via_way_nodes = trailing_elements(via_way_nodes)
        
            if isempty(intersect(trailing_via_way_nodes, trailing_to_way_nodes)) ||
            isempty(intersect(trailing_via_way_nodes, trailing_from_way_nodes))
                return false
            end
        catch
            # Restriction cannot be process - via ways cannot be joined on common trailing nodes
            return false
        end
    end

    return true
end

"""
Parse OpenStreetMap data into `Node`, `Way` and `Restriction` objects.
# TODO 
- Implement proper handler for cleaning tags of railways, e.g. Tunnels, Bridges
- Generalise relation handling - currently only does road turn restrictions  
"""
function parse_osm_network_dict(osm_network_dict::AbstractDict, 
                                network_type::Union{Symbol,Dict{String, Array{String,1}}}=:drive,
                                restriction_type::Symbol=:none)::OSMGraph
    U = DEFAULT_DATA_TYPES[:OSM_INDEX]
    T = DEFAULT_DATA_TYPES[:OSM_ID]
    W = DEFAULT_DATA_TYPES[:OSM_EDGE_WEIGHT]
    
    highways = Dict{T,Way{T}}()
    highway_nodes = Set{Integer}([])
    for way in osm_network_dict["way"]
        if haskey(way, "tags") && haskey(way, "nodes")
            tags = way["tags"]
            if is_highway(tags) && matches_network_type(tags, network_type)
                tags["maxspeed"] = maxspeed(tags)
                tags["lanes"] = lanes(tags)
                tags["oneway"] = is_oneway(tags)
                tags["reverseway"] = is_reverseway(tags)
                nds = way["nodes"]
                union!(highway_nodes, nds)
                id = way["id"]
                highways[id] = Way(id, nds, tags)
            elseif is_railway(tags) && matches_network_type(tags, network_type)
                tags["rail_type"] = haskey(tags,"railway") ? tags["railway"] : "unknown"
                tags["electrified"] = haskey(tags,"electrified") ? tags["electrified"] : "unknown"
                tags["gauge"] = haskey(tags,"gauge") ? tags["gauge"] : nothing
                tags["usage"] = haskey(tags,"usage") ? tags["usage"] :  "unknown"
                tags["name"] = haskey(tags,"name") ? tags["name"] : "unknown"
                tags["lanes"] = haskey(tags,"tracks") ? tags["tracks"] : 1  # usually track are drawn seprately in OSM.
                # Placeholder: These tags are not used for Rail, but required for graph construction. TODO how to handle
                tags["maxspeed"] = maxspeed(tags)
                tags["oneway"] = is_oneway(tags)
                tags["reverseway"] = is_reverseway(tags)
                nds = way["nodes"]
                union!(highway_nodes, nds)
                id = way["id"]
                highways[id] = Way(id, nds, tags)
            end
        end
    end

    nodes = Dict{T,Node{T}}()
    for node in osm_network_dict["node"]
        id = node["id"]
        if id in highway_nodes
            nodes[id] = Node{T}(
                id,
                GeoLocation(node["lat"], node["lon"]),
                haskey(node, "tags") ? node["tags"] : Dict{String,Any}()
            )
        end
    end
    
    restrictions = Dict{T,Restriction{T}}() # Currently Hardcoded processing of relations for road turn restriction
    if haskey(osm_network_dict, "relation")
        for relation in osm_network_dict["relation"]
            if haskey(relation, "tags") && haskey(relation, "members")
                tags = relation["tags"]
                members = relation["members"]

                if is_restriction(tags) && is_valid_restriction(members, highways)
                    restriction_kwargs = DefaultDict(Vector)
                    for member in members
                        key = "$(member["role"])_$(member["type"])"
                        if key == "via_way"
                            push!(restriction_kwargs[Symbol(key)], member["ref"])
                        else
                            restriction_kwargs[Symbol(key)] = member["ref"]
                        end
                    end

                    id = relation["id"]
                    restrictions[id] = Restriction{T}(
                        id=id,
                        tags=tags,
                        type=haskey(restriction_kwargs, :via_way) ? "via_way" : "via_node",
                        is_exclusion=occursin("no", tags["restriction"]) ? true : false,
                        is_exclusive=occursin("only", tags["restriction"]) ? true : false,
                        ;restriction_kwargs...
                    )
                end
            end
        end
    end
    return OSMGraph{U,T,W}(nodes=nodes, highways=highways, restrictions=restrictions)
end

"""
Parse OpenStreetMap data downloaded in `:xml` or `:osm` format into a dictionary consistent with data downloaded in `:json` format.
"""
function parse_xml_dict_to_json_dict(dict::AbstractDict)::AbstractDict
    # This function is needed so dict parsed from xml is consistent with dict parsed from json
    for (type, elements) in dict
        for (i, el) in enumerate(elements)
            !(el isa AbstractDict) && continue

            if haskey(el, "tag")
                dict[type][i]["tags"] = Dict{String,Any}(tag["k"] => tag["v"] for tag in el["tag"] if tag["k"] isa String)
                delete!(dict[type][i], "tag")
            end

            if haskey(el, "member")
                dict[type][i]["members"] = pop!(dict[type][i], "member") # rename
            end

            if haskey(el, "nd")
                dict[type][i]["nodes"] = [nd["ref"] for nd in el["nd"]]
                delete!(dict[type][i], "nd")
            end
        end
    end

    return dict
end

"""
Parse OpenStreetMap data downloaded in `:xml` or `:osm` format into a dictionary.
"""
function osm_dict_from_xml(osm_xml_object::XMLDocument)::AbstractDict
    root_node = root(osm_xml_object)
    dict = xml_to_dict(root_node, OSM_METADATA)
    return parse_xml_dict_to_json_dict(dict)
end

"""
Reorder OpenStreetMap data downloaded in `:json` format so items are groups by type.
"""
function osm_dict_from_json(osm_json_object::AbstractDict)::AbstractDict
    dict = DefaultDict(Vector)

    for el in osm_json_object["elements"]
        push!(dict[el["type"]], el)
    end

    return dict
end

"""
Initialises the OSMGraph object from OpenStreetMap data downloaded in `:xml` or `:osm` format.
"""
function init_graph_from_object(osm_xml_object::XMLDocument, 
                                network_type::Union{Symbol,Dict{String, Array{String,1}}}=:drive,
                                restriction_type::Symbol=:none)::OSMGraph
    dict_to_parse = osm_dict_from_xml(osm_xml_object)
    return parse_osm_network_dict(dict_to_parse, network_type, restriction_type)
end

"""
Initialises the OSMGraph object from OpenStreetMap data downloaded in `:json` format.
"""
function init_graph_from_object(osm_json_object::AbstractDict,
                                network_type::Union{Symbol,Dict{String, Array{String,1}}}=:drive,
                                restriction_type::Symbol=:none)::OSMGraph
    dict_to_parse = osm_dict_from_json(osm_json_object)
    return parse_osm_network_dict(dict_to_parse, network_type, restriction_type)
end
