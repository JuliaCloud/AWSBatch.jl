using Documenter, AWSBatch

makedocs(;
    modules=[AWSBatch],
    format=Documenter.HTML(
        prettyurls=get(ENV, "CI", nothing) == "true",
        assets=[
            "assets/invenia.css",
        ],
    ),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/JuliaCloud/AWSBatch.jl/blob/{commit}{path}#L{line}",
    sitename="AWSBatch.jl",
    authors="Invenia Technical Computing",
    strict = true,
    checkdocs = :none,
)

deploydocs(;
    repo="github.com/JuliaCloud/AWSBatch.jl",
    push_preview=true,
)
