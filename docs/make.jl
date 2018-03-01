using Documenter, AWSBatch

makedocs(;
    modules=[AWSBatch],
    format=:html,
    pages=[
        "Home" => "index.md",
    ],
    repo="https://gitlab.invenia.ca/invenia/AWSBatch.jl/blob/{commit}{path}#L{line}",
    sitename="AWSBatch.jl",
    authors="Nicole Epp",
    assets=[
        "assets/invenia.css",
        "assets/logo.png",
    ],
)
