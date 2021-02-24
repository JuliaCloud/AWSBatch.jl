# AWSBatch

[![Latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://invenia.pages.invenia.ca/AWSBatch.jl/)
[![Build Status](https://gitlab.invenia.ca/invenia/AWSBatch.jl/badges/master/build.svg)](https://gitlab.invenia.ca/invenia/AWSBatch.jl/commits/master)
[![Coverage](https://gitlab.invenia.ca/invenia/AWSBatch.jl/badges/master/coverage.svg)](https://gitlab.invenia.ca/invenia/AWSBatch.jl/commits/master)

# Running the tests

To run the online AWS Batch tests you must first set the environmental variables `TESTS` and
`AWS_STACKNAME`.

```julia
ENV["TESTS"] = "batch"
ENV["AWS_STACKNAME"] = "aws-batch-manager-test"
```

To make an `aws-batch-manager-test` compatible stack you can use the CloudFormation template [test/batch.yml](./test/batch.yml).
