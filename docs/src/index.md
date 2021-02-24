# AWSBatch

[![Docs: stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliacloud.github.io/AWSBatch.jl/stable)
[![CI](https://github.com/JuliaCloud/AWSBatch.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaCloud/AWSBatch.jl/actions/workflows/CI.yml)

AWSBatch.jl provides a small set of methods for working with AWS Batch jobs from julia.

## Installation

AWSBatch assumes that you already have an AWS account configured with:

1. An [ECR repository](https://aws.amazon.com/ecr/) and a docker image pushed to it [[1]](http://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html).
2. An [IAM role](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html) to apply to the batch jobs.
3. A compute environment and job queue for submitting jobs to [[2]](http://docs.aws.amazon.com/batch/latest/userguide/Batch_GetStarted.html#first-run-step-2).

Please review the
["Getting Started with AWS Batch"](http://docs.aws.amazon.com/batch/latest/userguide/Batch_GetStarted.html) guide and example
[CloudFormation template](https://s3-us-west-2.amazonaws.com/cloudformation-templates-us-west-2/Managed_EC2_Batch_Environment.template) for more details.

## Basic Usage

```julia
julia> using AWSBatch

julia> job = run_batch(
           name="Demo",
           definition="AWSBatchJobDefinition",
           queue="AWSBatchJobQueue",
           image = "000000000000.dkr.ecr.us-east-1.amazonaws.com/demo:latest",
           role = "arn:aws:iam::000000000000:role/AWSBatchJobRole",
           vcpus = 1,
           memory = 1024,
           cmd = `julia -e 'println("Hello World!")'`,
       )
AWSBatch.BatchJob("00000000-0000-0000-0000-000000000000")

julia> wait(job, [AWSBatch.SUCCEEDED])
true

julia> results = log_events(job)
1-element Array{AWSBatch.LogEvent,1}:
 AWSBatch.LogEvent("00000000000000000000000000000000000000000000000000000000", 2018-04-23T19:41:18.765, 2018-04-23T19:41:18.677, "Hello World!")
```

AWSBatch also supports Memento logging for more detailed usage information.

## API

```@docs
run_batch()
```

### BatchJob

```@docs
AWSBatch.BatchJob
AWSBatch.submit(::AbstractString, ::JobDefinition, ::AbstractString)
AWSBatch.describe(::BatchJob)
AWSBatch.JobDefinition(::BatchJob)
AWSBatch.status(::BatchJob)
Base.wait(::Function, ::BatchJob)
Base.wait(::BatchJob, ::Vector{JobState}, ::Vector{JobState})
AWSBatch.log_events(::BatchJob)
```

### JobDefinition

```@docs
AWSBatch.JobDefinition
AWSBatch.job_definition_arn(::AbstractString)
AWSBatch.register(::AbstractString)
AWSBatch.deregister(::JobDefinition)
AWSBatch.isregistered(::JobDefinition)
AWSBatch.describe(::JobDefinition)
```

### JobState

```@docs
AWSBatch.JobState
```

### LogEvent

```@docs
AWSBatch.LogEvent
```
