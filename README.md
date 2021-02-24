# AWSBatch
[![CI](https://github.com/JuliaCloud/AWSBatch.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaCloud/AWSBatch.jl/actions/workflows/CI.yml)
[![Docs: stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliacloud.github.io/AWSBatch.jl/stable)
[![Docs: dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliacloud.github.io/AWSBatch.jl/dev)

# Running the tests

To run the online AWS Batch tests you must first set the environmental variables `TESTS` and
`AWS_STACKNAME`.

```julia
ENV["TESTS"] = "batch"
ENV["AWS_STACKNAME"] = "aws-batch-manager-test"
```

To make an `aws-batch-manager-test` compatible stack you can use the CloudFormation template [test/batch.yml](./test/batch.yml).
