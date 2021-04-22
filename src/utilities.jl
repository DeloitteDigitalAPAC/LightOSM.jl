"""
    string_deserializer(format::Symbol)::Function

Retrieves string deserializer for downloaded OpenStreetMap data.

# Arguments
- `format::Symbol`: Format of OpenStreetMap darta `:xml`, `:osm` or `:json`.

# Return
- `Function`: Either LightXML or JSON parser.
"""
function string_deserializer(format::Symbol)::Function
    if format == :xml || format == :osm
        return LightXML.parse_string
    elseif format == :json
        return JSON.parse
    else
        throw(ArgumentError("String deserializer for $format format does not exist"))
    end
end

"""
    file_deserializer(format::Symbol)::Function

Retrieves file deserializer for downloaded OpenStreetMap data.

# Arguments
- `format::Symbol`: Format of OpenStreetMap darta `:xml`, `:osm` or `:json`.

# Return
- `Function`: Either LightXML or JSON parser. 
"""
function file_deserializer(format::Symbol)::Function
    if format == :xml || format == :osm
        return LightXML.parse_file
    elseif format == :json
        return JSON.parsefile
    else
        throw(ArgumentError("File deserializer for $format format does not exist"))
    end
end

"""
    tryparse_string_to_number(str::AbstractString)::Union{Number,AbstractString}

Attempts to parse a stringified number as an Integer or Float.
"""
function tryparse_string_to_number(str::AbstractString)::Union{Number,AbstractString}
    result = tryparse(Int, str)
    if !(result isa Nothing)
        return result
    end

    result = tryparse(Float64, str)
    if !(result isa Nothing)
        return result
    end

    return str
end

"""
    remove_non_numeric(str::AbstractString)::Number

Removes any non numeric characters from a string, then converts it to a number.
"""
function remove_non_numeric(str::AbstractString)::Number
    numeric_only = replace(str, r"[^\d\.]" => "")
    return isempty(numeric_only) ? 0 : tryparse_string_to_number(numeric_only)
end

"""
    remove_sub_string_after(str::AbstractString, after::AbstractString)::AbstractString

Removes all characters in a string that occurs `after` some input match pattern.
"""
function remove_sub_string_after(str::AbstractString, after::AbstractString)::AbstractString
    regex = Regex("$after.*\$")
    return replace(str, regex => "")
end

"""
    remove_numeric(str::AbstractString)::AbstractString

Removes numeric characters from a string.
"""
function remove_numeric(str::AbstractString)::AbstractString
    return replace(str, r"[\d\.]" => "")
end

"""
    xml_to_dict(root_node::Union{XMLNode,XMLElement}, attributes_to_exclude::Set=Set())::AbstractDict

Parses a LightXML object to a dictionary.

# Arguments
- `root_node::Union{XMLNode,XMLElement}`: LightXML object to parse.
- `attributes_to_exclude::Set=Set()`: Set of tags to ignore when parsing.

# Return
- `AbstractDict`: XML parsed as a dictionary.
"""
function xml_to_dict(root_node::Union{XMLNode,XMLElement}, attributes_to_exclude::Set=Set())::AbstractDict
    result = Dict()

    for a in attributes(root_node)
        if !(name(a) in attributes_to_exclude)
            result[name(a)] = tryparse_string_to_number(value(a))
        end
    end

    if has_children(root_node)
        for c in collect(child_elements(root_node))
            key = name(c)

            if key in attributes_to_exclude
                continue
            end

            if haskey(result, name(c))
                push!(result[key], xml_to_dict(c, attributes_to_exclude))
            else
                result[key] = [xml_to_dict(c, attributes_to_exclude)]
            end
        end
    end
    
    return result
end

"""
Returns the first and last element of an array.
"""
trailing_elements(array::AbstractArray)::AbstractArray = [array[1], array[end]]

"""
Returns the common trailing element (first or last element) of two arrays if it exists.
"""
function first_common_trailing_element(a1::AbstractArray{T}, a2::AbstractArray{T})::T where T <: Any
    intersection = intersect(trailing_elements(a1), trailing_elements(a2))
    return length(intersection) >= 1 ? intersection[1] : throw(ArgumentError("No common trailinging elements between $a1 and $a2"))
end

"""
Joins two arrays into a single array on a common trailing element.
"""
function join_two_arrays_on_common_trailing_elements(a1::AbstractArray{T}, a2::AbstractArray{T})::AbstractArray{T} where T <: Any
    el = first_common_trailing_element(a1, a2)

    if el == a1[1] == a2[1]
        return [reverse(a1)..., a2[2:end]...]
    elseif el == a1[1] == a2[end]
        return [reverse(a1)..., reverse(a2)[2:end]...]
    elseif el == a1[end] == a2[1]
        return [a1..., a2[2:end]...]
    elseif el == a1[end] == a2[end]
        return [a1..., reverse(a2)[2:end]...]
    end 
end

"""
Joins an array of arrays into a single array, on common trailing elements.
"""
function join_arrays_on_common_trailing_elements(arrays::AbstractArray{T}...)::AbstractArray{T} where T <: Any
    current = arrays[1]
    others = setdiff(arrays, [current])

    if !isempty(others)
        for (i, other) in enumerate(others)
            try
                current = join_two_arrays_on_common_trailing_elements(current, other)
                deleteat!(others, i)
                return join_arrays_on_common_trailing_elements(current, others...)
            catch
                continue
            end
        end
        throw(ErrorException("Could not join $current on $others"))
    else
        return current
    end
end

"""
    delete_from_dict!(dict::AbstractDict, items_to_delete::Union{AbstractArray,AbstractSet}, how::Symbol=:on_key)

Deletes key-value pairs from a dictionary.

# Arguments
- `dict::AbstractDict`: Any dictionary to delete from.
- `items_to_delete::Union{AbstractArray,AbstractSet}`: List of items to delete, either keys or values.
- `how::Symbol=:on_key`: To delete `:on_key` or `:on_value`.

# Return
- `AbstractDict`: Filtered dictionary.
"""
function delete_from_dict!(dict::AbstractDict, items_to_delete::Union{AbstractArray,AbstractSet}, how::Symbol=:on_key)
    if how == :on_key
        for k in items_to_delete
            delete!(dict, k)
        end
    elseif how == :on_value
        for (k, v) in dict
            if v in items_to_delete
                delete!(dict, k)
            end
        end
    else
        throw(ErrorException("Choose `how` as either `:on_key` or `on_value`"))
    end
end

"""
    flatten(array::AbstractArray)::AbstractArray

Flattens an array of arrays.
"""
function flatten(array::AbstractArray)::AbstractArray
    flattened = collect(Iterators.flatten(array))
    if any(x -> typeof(x) <: AbstractArray, flattened)
        return flatten(flattened)
    end
    return flattened
end
