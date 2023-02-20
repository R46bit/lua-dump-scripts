local DUMP_FOLDER = "X:/dump"
local DUMP_LOG_FILE = DUMP_FOLDER .. "/dump-csharp.log"
local DUMP_CS_FILE = DUMP_FOLDER .. "/dump-csharp.cs"

local SYSTEM_NAMES = {
    ["System.Int32"] = "int",
    ["System.UInt32"] = "uint",
    ["System.Int16"] = "short",
    ["System.UInt16"] = "ushort",
    ["System.Int64"] = "long",
    ["System.UInt64"] = "ulong",
    ["System.Byte"] = "byte",
    ["System.SByte"] = "sbyte",
    ["System.Boolean"] = "bool",
    ["System.Single"] = "float",
    ["System.Double"] = "double",
    ["System.String"] = "string",
    ["System.Char"] = "char",
    ["System.Object"] = "object",
    ["System.Void"] = "void"
}

local log = io.open(DUMP_LOG_FILE, "w")

local function get_type_visibility_string(type)
    local string = ""
    local attributes = type.Attributes
    local visibility = attributes & CS.System.Reflection.TypeAttributes.VisibilityMask
    if (visibility == CS.System.Reflection.TypeAttributes.Public) then
        string = string .. "public "
    elseif (visibility == CS.System.Reflection.TypeAttributes.NotPublic) or
        (visibility == CS.System.Reflection.TypeAttributes.NestedFamANDAssem) or
        (visibility == CS.System.Reflection.TypeAttributes.NestedAssembly) then
        string = string .. "internal "
    elseif (visibility == CS.System.Reflection.TypeAttributes.NestedPrivate) then
        string = string .. "private "
    elseif (visibility == CS.System.Reflection.TypeAttributes.NestedFamily) then
        string = string .. "protected "
    elseif (visibility == CS.System.Reflection.TypeAttributes.NestedFamORAssem) then
        string = string .. "internal "
    end
    return string
end

local function get_type_string(type)
    local string = get_type_visibility_string(type)
    local attributes = type.Attributes
    if (attributes & CS.System.Reflection.TypeAttributes.Sealed).value__ ~= 0 and
        (attributes & CS.System.Reflection.TypeAttributes.Abstract).value__ ~= 0 then
        string = string .. "static "
    elseif (attributes & CS.System.Reflection.TypeAttributes.Abstract).value__ ~= 0 and
        (attributes & CS.System.Reflection.TypeAttributes.Interface).value__ == 0 then
        string = string .. "abstract "
    elseif (attributes & CS.System.Reflection.TypeAttributes.Sealed).value__ ~= 0 and
        (not type.IsEnum or not type.IsValueType) then
        string = string .. "sealed "
    end
    if (attributes & CS.System.Reflection.TypeAttributes.Interface).value__ ~= 0 then
        string = string .. "interface "
    elseif type.IsEnum then
        string = string .. "enum "
    elseif type.IsValueType then
        string = string .. "struct "
    else
        string = string .. "class "
    end
    return string
end

local function get_reflected_type(type)
    local name = type.Name
    if type.ReflectedType ~= nil and not type.ReflectedType.IsGenericType then
        -- log:write(string.format("%s %s\n", type, type.ReflectedType))
        name = type.ReflectedType.Name .. "." .. name
    end
    return name
end

local function get_runtime_type_name(type, alias)
    if type.IsArray then
        return get_runtime_type_name(type:GetElementType(), alias) .. "[]"
    elseif type.IsPointer then
        return get_runtime_type_name(type:GetElementType(), alias) .. "*"
    elseif type.IsByRef then
        return get_runtime_type_name(type:GetElementType(), alias) .. "&"
    elseif type.IsGenericType then
        local name = type:GetGenericTypeDefinition().Name
        local pos = name:find("`")
        if pos ~= nil then
            name = name:sub(1, pos - 1)
        end
        local generic_args = type:GetGenericArguments()
        name = name .. "<"
        for i = 0, generic_args.Length - 1 do
            if i ~= 0 then
                name = name .. ", "
            end
            name = name .. get_runtime_type_name(generic_args[i], alias)
        end
        name = name .. ">"
        return name
    else
        if alias and type.Namespace == "System" then
            local name = SYSTEM_NAMES[type.Namespace .. "." .. type.Name]
            if name ~= nil then
                return name
            end
        end
        return get_reflected_type(type)
    end
end

local function get_runtime_type_name_alias(type)
    return get_runtime_type_name(type, true)
end

local function get_method_type_string(method)
    local string = ""
    local attributes = method.Attributes
    local access = attributes & CS.System.Reflection.MethodAttributes.MemberAccessMask
    if (access == CS.System.Reflection.MethodAttributes.Private) then
        string = string .. "private "
    elseif (access == CS.System.Reflection.MethodAttributes.Public) then
        string = string .. "public "
    elseif (access == CS.System.Reflection.MethodAttributes.Family) then
        string = string .. "protected "
    elseif (access == CS.System.Reflection.MethodAttributes.Assembly) or
        (access == CS.System.Reflection.MethodAttributes.FamANDAssem) then
        string = string .. "internal "
    elseif (access == CS.System.Reflection.MethodAttributes.FamORAssem) then
        string = string .. "protected internal "
    end
    if (attributes & CS.System.Reflection.MethodAttributes.Static).value__ ~= 0 then
        string = string .. "static "
    end
    if (attributes & CS.System.Reflection.MethodAttributes.Abstract).value__ ~= 0 then
        string = string .. "abstract "
        if (attributes & CS.System.Reflection.MethodAttributes.VtableLayoutMask) ==
            CS.System.Reflection.MethodAttributes.ReuseSlot then
            string = string .. "override "
        end
    elseif (attributes & CS.System.Reflection.MethodAttributes.Final).value__ ~= 0 then
        if (attributes & CS.System.Reflection.MethodAttributes.VtableLayoutMask) ==
            CS.System.Reflection.MethodAttributes.ReuseSlot then
            string = string .. "sealed override "
        end
    elseif (attributes & CS.System.Reflection.MethodAttributes.Virtual).value__ ~= 0 then
        if (attributes & CS.System.Reflection.MethodAttributes.VtableLayoutMask) ==
            CS.System.Reflection.MethodAttributes.NewSlot then
            string = string .. "virtual "
        else
            string = string .. "override "
        end
    end
    if (attributes & CS.System.Reflection.MethodAttributes.PinvokeImpl).value__ ~= 0 then
        string = string .. "extern "
    end
    return string
end

local function do_dump_csharp_field(file, field)
    local attributes = field.Attributes
    local access = attributes & CS.System.Reflection.FieldAttributes.FieldAccessMask
    if (access == CS.System.Reflection.FieldAttributes.Private) then
        file:write("private ")
    elseif (access == CS.System.Reflection.FieldAttributes.Public) then
        file:write("public ")
    elseif (access == CS.System.Reflection.FieldAttributes.Family) then
        file:write("protected ")
    elseif (access == CS.System.Reflection.FieldAttributes.Assembly) or
        (access == CS.System.Reflection.FieldAttributes.FamANDAssem) then
        file:write("internal ")
    elseif (access == CS.System.Reflection.FieldAttributes.FamORAssem) then
        file:write("protected internal ")
    end
    if field.IsLiteral then
        file:write("const ")
    end
    if field.IsStatic then
        file:write("static ")
    end
    if field.IsInitOnly then
        file:write("readonly ")
    end
    file:write(get_runtime_type_name_alias(field.FieldType) .. " " .. field.Name)
    if field.IsLiteral then
        if field.FieldType.Namespace == "System" and field.FieldType.Name == "String" then
            file:write(string.format(" = \"%s\";", field:GetRawConstantValue()))
        else
            file:write(string.format(" = %s;", field:GetRawConstantValue()))
        end
    else
        local value = field:GetFieldOffset()
        if value & 0x8000000000000000 ~= 0 then
            value = -value
            file:write(string.format("; // -0x%X", value))
        else
            file:write(string.format("; // 0x%X", value))
        end
    end
    file:write("\n")
end

local function do_dump_csharp_property(file, property)
    if property.CanRead then
        local method = property:GetGetMethod(true)
        if method ~= nil then
            file:write(get_method_type_string(method))
        else
            log:write("property " .. property.Name .. " has no getter\n")
            file:write(get_type_visibility_string(property.PropertyType))
        end
    elseif property.CanWrite then
        local method = property:GetSetMethod(true)
        if method ~= nil then
            file:write(get_method_type_string(method))
        else
            log:write("property " .. property.Name .. " has no setter\n")
            file:write(get_type_visibility_string(property.PropertyType))
        end
    else
        file:write(get_type_visibility_string(property.PropertyType))
    end
    file:write(get_runtime_type_name_alias(property.PropertyType) .. " " .. property.Name .. " { ")
    if property.CanRead then
        file:write("get; ")
    end
    if property.CanWrite then
        file:write("set; ")
    end
    file:write("}\n")
end

local function do_dump_csharp_method(file, type, method, is_ctor)
    if is_ctor then
        file:write(get_method_type_string(method))
        file:write("void " .. method.Name)
    else
        file:write(get_method_type_string(method))
        file:write(get_runtime_type_name_alias(method.ReturnType) .. " " .. method.Name)
        local arguments = method:GetGenericArguments()
        if arguments.Length > 0 then
            file:write("<")
            for i = 0, arguments.Length - 1 do
                local argument = arguments[i]
                if i ~= 0 then
                    file:write(", ")
                end
                file:write(get_runtime_type_name_alias(argument))
            end
            file:write(">")
        end
    end
    file:write("(")
    local parameters = method:GetParameters()
    for i = 0, parameters.Length - 1 do
        local parameter = parameters[i]
        if i ~= 0 then
            file:write(", ")
        end
        local name = get_runtime_type_name_alias(parameter.ParameterType)
        local pos = name:find("&")
        if pos ~= nil then
            name = name:sub(1, pos - 1)
            if parameter.IsIn then
                name = "in " .. name
            elseif parameter.IsOut then
                name = "out " .. name
            else
                name = "ref " .. name
            end
        end
        file:write(name .. " " .. parameter.Name)
        local status, err = pcall(function()
            if parameter.IsOptional then
                if parameter.ParameterType.IsEnum then
                    if parameter.DefaultValue == nil then
                        file:write(" = 0")
                    elseif parameter.DefaultValue.value__ == nil then
                        file:write(" = 0")
                    else
                        file:write(string.format(" = %d", parameter.DefaultValue.value__))
                    end
                else
                    if parameter.ParameterType.Namespace == "System" and parameter.ParameterType.Name == "String" then
                        file:write(string.format(" = \"%s\"", parameter.DefaultValue))
                    else
                        file:write(string.format(" = %s", parameter.DefaultValue))
                    end
                end
            end
        end)
        if not status then
            log:write(err .. "\n")
        end
    end
    file:write(") { }\n")
end

local function do_dump_csharp_type(file, type)
    local namespace = type.Namespace
    if namespace == nil then
        file:write("// Namespace:\n")
    else
        file:write(string.format("// Namespace: %s\n", namespace))
    end

    file:write(get_type_string(type) .. get_runtime_type_name(type, false))
    local once = false
    local base_type = type.BaseType
    if base_type ~= nil then
        local name = get_runtime_type_name_alias(base_type)
        -- log:write(string.format("%s %s\n", type, name))
        if base_type.Namespace == "System" then
            if name ~= "object" and name ~= "ValueType" and name ~= "Enum" then
                once = true
            end
        end
        if once then
            file:write(" : " .. name)
        end
    end
    local interfaces = type:GetInterfaces()
    if interfaces.Length > 0 then
        for i = 0, interfaces.Length - 1 do
            local interface = interfaces[i]
            if not once then
                once = true
                file:write(" : ")
            else
                file:write(", ")
            end
            file:write(get_runtime_type_name_alias(interface))
        end
    end

    file:write("\n{")

    local flags = CS.System.Reflection.BindingFlags.Instance | CS.System.Reflection.BindingFlags.Static |
                      CS.System.Reflection.BindingFlags.Public | CS.System.Reflection.BindingFlags.NonPublic

    local fields = type:GetFields(flags)
    if fields.Length > 0 then
        local once = false
        for j = 0, fields.Length - 1 do
            local field = fields[j]
            if field.DeclaringType == type then
                if not once then
                    file:write("\n")
                    file:write("\t// Fields\n")
                    once = true
                end
                file:write("\t")
                do_dump_csharp_field(file, field)
            end
        end
    end

    local properties = type:GetProperties(flags)
    if properties.Length > 0 then
        local once = false
        for j = 0, properties.Length - 1 do
            local property = properties[j]
            if property.DeclaringType == type then
                if not once then
                    file:write("\n")
                    file:write("\t// Properties\n")
                    once = true
                end
                file:write("\t")
                do_dump_csharp_property(file, property)
            end
        end
    end

    local constructors = type:GetConstructors(flags)
    if constructors.Length > 0 then
        local once = false
        for j = 0, constructors.Length - 1 do
            local constructor = constructors[j]
            if constructor.DeclaringType == type then
                if not once then
                    file:write("\n")
                    file:write("\t// Constructors\n")
                    once = true
                end
                file:write("\t")
                do_dump_csharp_method(file, type, constructor, true)
            end
        end
    end

    local methods = type:GetMethods(flags)
    if methods.Length > 0 then
        local once = false
        for j = 0, methods.Length - 1 do
            local method = methods[j]
            if method.DeclaringType == type then
                if not once then
                    file:write("\n")
                    file:write("\t// Methods\n")
                    once = true
                end
                file:write("\t")
                do_dump_csharp_method(file, type, method, false)
            end
        end
    end

    file:write("}\n")
end

local function do_dump_csharp()
    local file = io.open(DUMP_CS_FILE, "w")

    local assemblies = CS.System.AppDomain.CurrentDomain:GetAssemblies()
    for i = 0, assemblies.Length - 1 do
        local assembly = assemblies[i]
        file:write(string.format("// Assembly %d: %s\n", i, assembly:GetSimpleName()))
    end

    for i = 0, assemblies.Length - 1 do
        local assembly = assemblies[i]
        local types = assembly:GetTypes()
        log:write(string.format("dumping types in assembly %d: %s, total: %d\n", i, assembly:GetSimpleName(),
            types.Length))
        for j = 0, types.Length - 1 do
            local type = types[j]
            file:write("\n")
            do_dump_csharp_type(file, type)
        end
    end

    file:close()
end

local function main()
    log:write("start dumping csharp to " .. DUMP_CS_FILE .. "\n")
    do_dump_csharp()
    log:write("dumping csharp done\n")
end

local function on_error(error)
    log:write("dumping csharp failed, error: " .. error .. "\n")
end

xpcall(main, on_error)

log:close()
