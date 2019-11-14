# TODO: Temporary until this is turned into a package
using Pkg: Pkg

# https://github.com/JuliaLang/julia/pull/33128
if VERSION < v"1.4.0-DEV.397"
    function pkgdir(m::Module)
        rootmodule = Base.moduleroot(m)
        path = pathof(rootmodule)
        path === nothing && return nothing
        return dirname(dirname(path))
    end
end

"""
    @__VERSION__ -> Union{VersionNumber, Nothing}

Get the `VersionNumber` of the package which expands this macro. If executed outside of a
package `nothing` will be returned.
"""
macro __VERSION__()
    pkg_dir = pkgdir(__module__)

    if pkg_dir !== nothing
        project_data = Pkg.TOML.parsefile(Pkg.Types.projectfile_path(pkg_dir))
        return VersionNumber(project_data["version"])
    else
        return nothing
    end
end
