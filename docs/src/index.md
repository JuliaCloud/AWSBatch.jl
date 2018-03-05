# AWSBatch

[![Latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://doc.invenia.ca/invenia/AWSBatch.jl/master)
[![Build Status](https://gitlab.invenia.ca/invenia/AWSBatch.jl/badges/master/build.svg)](https://gitlab.invenia.ca/invenia/AWSBatch.jl/commits/master)
[![Coverage](https://gitlab.invenia.ca/invenia/AWSBatch.jl/badges/master/coverage.svg)](https://gitlab.invenia.ca/invenia/AWSBatch.jl/commits/master)

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

julia> using Memento

julia> Memento.config("info"; fmt="[{level} | {name}]: {msg}")
Logger(root)

julia> job = BatchJob(
           name="Demo",
           definition="AWSBatchJobDefinition",
           queue="AWSBatchJobQueue",
           container=Dict(
           	"image" => "000000000000.dkr.ecr.us-east-1.amazonaws.com/demo:latest",
           	"role" => "arn:aws:iam::000000000000:role/AWSBatchJobRole",
           	"vcpus" => 1,
           	"memory" => 1024,
           	"cmd" => `julia -e 'println("Hello World!")'`,
           ),
       )
AWSBatch.BatchJob("", "Demo", AWSBatch.BatchJobDefinition("AWSBatchJobDefinition"), "AWSBatchJobQueue", "", AWSBatch.BatchJobContainer("000000000000.dkr.ecr.us-east-1.amazonaws.com/demo:latest", 1, 1024, "arn:aws:iam::000000000000:role/AWSBatchJobRole", `julia -e 'println("Hello World!")'`))

julia> submit(job)
[info | AWSBatch]: Registered job definition arn:aws:batch:us-east-1:000000000000:job-definition/AWSBatchJobDefinition:1.
[info | AWSBatch]: Submitted job Demo::00000000-0000-0000-0000-000000000000.
Dict{String,Any} with 2 entries:
  "jobId"   => "00000000-0000-0000-0000-000000000000"
  "jobName" => "Demo"

julia> wait(job, [AWSBatch.SUCCEEDED])
[info | AWSBatch]: Demo::00000000-0000-0000-0000-000000000000 status SUBMITTED
[info | AWSBatch]: Demo::00000000-0000-0000-0000-000000000000 status STARTING
[info | AWSBatch]: Demo::00000000-0000-0000-0000-000000000000 status SUCCEEDED
true

julia> results = logs(job)
[info | AWSBatch]: Fetching log events from Demo/default/00000000-0000-0000-0000-000000000000
[info | AWSBatch]: Hello World!
1-element Array{Any,1}:
 Dict{String,Any}(Pair{String,Any}("ingestionTime", 1505846649863),Pair{String,Any}("message", "Hello World!"),Pair{String,Any}("timestamp", 1505846649786),Pair{String,Any}("eventId", "00000000000000000000000000000000000000000000000000000000"))
```

## Public API

### BatchJob

```@docs
AWSBatch.BatchJob
AWSBatch.BatchJob()
AWSBatch.BatchStatus
AWSBatch.isregistered(::BatchJob)
AWSBatch.register!(::BatchJob)
AWSBatch.deregister!(::BatchJob)
AWSBatch.describe(::BatchJob)
AWSBatch.submit(::BatchJob)
Base.wait(::BatchJob, ::Vector{BatchStatus}, ::Vector{BatchStatus})
AWSBatch.logs(::BatchJob)
```

### BatchJobDefinition

```@docs
AWSBatch.BatchJobDefinition
AWSBatch.describe(::BatchJobDefinition)
AWSBatch.isregistered(::BatchJobDefinition)
```

### BatchJobContainer

```@docs
AWSBatch.BatchJobContainer
AWSBatch.BatchJobContainer(::Associative)
```

## Private API

```@docs
AWSBatch.lookupARN(::BatchJob)
AWSBatch.update!(::BatchJobContainer, ::Associative)
```