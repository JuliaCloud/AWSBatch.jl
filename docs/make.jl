using Documenter, AWSBatch

makedocs(;
    modules=[AWSBatch],
    format=Documenter.HTML(
        prettyurls=get(ENV, "CI", nothing) == "true",
        assets=[
            "assets/invenia.css",
            "assets/logo.png",
        ],
    ),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://gitlab.invenia.ca/invenia/AWSBatch.jl/blob/{commit}{path}#L{line}",
    sitename="AWSBatch.jl",
    authors="Invenia Technical Computing",
    strict = true,
    checkdocs = :none,
)
