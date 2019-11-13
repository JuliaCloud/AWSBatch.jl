# TODO: Temporary until this is turned into a package
using Pkg

"""
    @__VERSION__ -> Union{VersionNumber, Nothing}

Get the `VersionNumber` of the package which expands this macro. If executed outside of a
package `nothing` will be returned.
"""
macro __VERSION__()
    ctxt = Pkg.Types.Context()
    pkg_id = Base.PkgId(__module__)
    pkg_id.uuid === nothing && return nothing

    project = ctxt.env.project
    project_name = @static if v"1.0-" <= VERSION < v"1.1-"
        project["name"]
    else
        project.name
    end

    pkg_info = if project_name == pkg_id.name
        project
    else
        _ctxt = @static VERSION < v"1.4-" ? ctxt.env : ctxt
        Pkg.Types.manifest_info(_ctxt, pkg_id.uuid)
    end

    version = @static if v"1.0-" <= VERSION < v"1.1-"
        VersionNumber(pkg_info["version"])
    elseif v"1.1-" <= VERSION < v"1.2-"
        VersionNumber(pkg_info.version)
    else
        pkg_info.version
    end

    return version
end
