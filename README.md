# AWSBatch

[![Latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://invenia.pages.invenia.ca/AWSBatch.jl/)
[![Build Status](https://gitlab.invenia.ca/invenia/AWSBatch.jl/badges/master/build.svg)](https://gitlab.invenia.ca/invenia/AWSBatch.jl/commits/master)
[![Coverage](https://gitlab.invenia.ca/invenia/AWSBatch.jl/badges/master/coverage.svg)](https://gitlab.invenia.ca/invenia/AWSBatch.jl/commits/master)

# Running the tests

To run the ONLINE batch tests you must first set the environmental variables `ONLINE` and
`AWS_STACKNAME`.

```julia
ENV["ONLINE"] = "batch"

ENV["AWS_STACKNAME"] = "aws-batch-manager-test"
```

To make an `aws-batch-manager-test` compatible stack you can use the AWSClusterManagers.jl
CloudFormation template [test/batch.yml](https://gitlab.invenia.ca/invenia/AWSClusterManagers.jl/blob/master/test/batch.yml).
