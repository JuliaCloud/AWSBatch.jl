using AWSBatch
using AWSBatch: LogEvent, describe_jobs, describe_job_definitions, register_job_definition,
    submit_job
using AWSCore: AWSConfig, AWSException
using AWSSDK.CloudWatchLogs: get_log_events
using AWSTools.CloudFormation: stack_output
using AWSTools.EC2: instance_region
using Dates
using Git_jll
using HTTP: HTTP
using Memento
using Memento.TestUtils: @test_log, @test_nolog
using Mocking
using Test

Mocking.activate()

# Controls the running of various tests: "local", "batch"
const TESTS = strip.(split(get(ENV, "TESTS", "local"), r"\s*,\s*"))

# Run the tests on a stack created with the "test/batch.yml" CloudFormation template
# found in AWSClusterMangers.jl
const AWS_STACKNAME = get(ENV, "AWS_STACKNAME", "")
const STACK = !isempty(AWS_STACKNAME) ? stack_output(AWS_STACKNAME) : Dict()
const JOB_TIMEOUT = 900
const LOG_TIMEOUT = 30

const JULIA_BAKED_IMAGE = let
    output = git() do git_path
        read(`$git_path ls-remote --tags https://github.com/JuliaLang/julia`, String)
    end
    tags = split(replace(output, r".*\/" => ""))
    versions = VersionNumber.(filter(v -> !endswith(v, "^{}"), tags))

    latest_version = maximum(versions)
    docker_tag = VERSION > latest_version ? "nightly" : "$VERSION"

    "468665244580.dkr.ecr.us-east-1.amazonaws.com/julia-baked:$docker_tag"
end

Memento.config!("debug"; fmt="[{level} | {name}]: {msg}")
const logger = getlogger(AWSBatch)
setlevel!(logger, "info")


# We've been having issues with the log stream being created but no log events are present.
# - https://gitlab.invenia.ca/invenia/AWSBatch.jl/issues/28
# - https://gitlab.invenia.ca/invenia/AWSBatch.jl/issues/30
#
# This function allows for us to wait if logs are not present but avoids blocking when
# logs are ready.
#
# Note: The timeout duration expects the job has reached the SUCCEEDED or FAILED state and
# is not expected to last long enough for a job to complete running.
function wait_for_log_events(job::BatchJob)
    events = nothing

    # Convert to Float64 until this is merged and we no longer use versions of Julia
    # without PR (probably Julia 1.5+): https://github.com/JuliaLang/julia/pull/35103
    timedwait(Float64(LOG_TIMEOUT); pollint=Float64(5)) do
        events = log_events(job)

        # Note: These warnings should assist in determining the special circumstances
        # the log events not being present. Eventually warnings should be removed.
        if events === nothing
            notice(logger, "Log stream for $(job.id) does not exist")
        elseif isempty(events)
            notice(logger, "No log events for $(job.id)")
        end

        # Wait for log stream to exist and contain at least one event
        events !== nothing && !isempty(events)
    end

    return events
end

include("mock.jl")

@testset "AWSBatch.jl" begin
    if "local" in TESTS
        include("compute_environment.jl")
        include("job_queue.jl")
        include("log_event.jl")
        include("job_state.jl")
        include("batch_job.jl")
        include("run_batch.jl")
    else
        warn(logger, "Skipping \"local\" tests. Set `ENV[\"TESTS\"] = \"local\"` to run.")
    end

    if "batch" in TESTS && !isempty(AWS_STACKNAME)
        @testset "AWS Batch" begin
            info(logger, "Running AWS Batch tests")

            @testset "Job Submission" begin
                definition = "aws-batch-test"

                # Append the job ID to the definition when running on the CI. Doing this
                # will allow this test to successfully reuse the job definition later when
                # concurrent CI jobs are running AWS Batch tests at the same time.
                if haskey(ENV, "CI_JOB_ID")
                    definition *= "-" * ENV["CI_JOB_ID"]
                end

                job = run_batch(;
                    name = "aws-batch-test",
                    definition = definition,
                    queue = STACK["JobQueueArn"],
                    image = JULIA_BAKED_IMAGE,
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = `julia -e 'println("Hello World!")'`,
                    parameters = Dict{String, String}("region" => "us-east-1"),
                )

                @test wait(job, [AWSBatch.SUCCEEDED]; timeout=JOB_TIMEOUT) == true
                @test status(job) == AWSBatch.SUCCEEDED

                events = wait_for_log_events(job)
                @test length(events) == 1
                @test first(events).message == "Hello World!"

                # Test job details were set correctly
                job_details = describe(job)
                @test job_details["jobName"] == "aws-batch-test"
                @test occursin(STACK["JobQueueArn"], job_details["jobQueue"])
                @test job_details["parameters"] == Dict("region" => "us-east-1")

                # Test job definition and container parameters were set correctly
                job_definition = JobDefinition(job)
                @test isregistered(job_definition) == true

                job_definition_details = first(describe(job_definition)["jobDefinitions"])

                @test job_definition_details["jobDefinitionName"] == definition
                @test job_definition_details["status"] == "ACTIVE"
                @test job_definition_details["type"] == "container"

                container_properties = job_definition_details["containerProperties"]
                @test container_properties["image"] == JULIA_BAKED_IMAGE
                @test container_properties["vcpus"] == 1
                @test container_properties["memory"] == 1024
                @test container_properties["command"] == [
                    "julia",
                    "-e",
                    "println(\"Hello World!\")"
                ]
                @test container_properties["jobRoleArn"] == STACK["JobRoleArn"]

                # Reuse job definition
                job = run_batch(;
                    name = "aws-batch-test",
                    definition = definition,
                    queue = STACK["JobQueueArn"],
                    image = JULIA_BAKED_IMAGE,
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = `julia -e 'println("Hello World!")'`,
                    parameters = Dict{String, String}("region" => "us-east-1"),
                )

                @test wait(job, [AWSBatch.SUCCEEDED]; timeout=JOB_TIMEOUT) == true
                @test status(job) == AWSBatch.SUCCEEDED

                # Test job definition and container parameters were set correctly
                job_definition_2 = JobDefinition(job)
                @test job_definition_2 == job_definition

                deregister(job_definition)
            end

            @testset "Job registration disallowed" begin
                @test_throws BatchEnvironmentError run_batch(;
                    name = "aws-batch-no-job-registration-test",
                    queue = STACK["JobQueueArn"],
                    image = JULIA_BAKED_IMAGE,
                    role = STACK["JobRoleArn"],
                    cmd = `julia -e 'println("Hello World!")'`,
                    parameters = Dict{String, String}("region" => "us-east-1"),
                    allow_job_registration = false,
                )
            end

            @testset "Job parameters" begin
                # Use parameter substitution placeholders in the command field
                command = Cmd(["julia", "-e", "Ref::juliacmd"])

                # Set a default output string when registering the job definition
                job_definition = register(
                    "aws-batch-parameters-test";
                    image=JULIA_BAKED_IMAGE,
                    role=STACK["JobRoleArn"],
                    vcpus=1,
                    memory=1024,
                    cmd=command,
                    region="us-east-1",
                    parameters=Dict("juliacmd" => "println(\"Default String\")"),
                )

                # Override the default output string
                job = run_batch(;
                    name = "aws-batch-parameters-test",
                    definition = job_definition,
                    queue = STACK["JobQueueArn"],
                    image = JULIA_BAKED_IMAGE,
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = command,
                    parameters=Dict("juliacmd" => "println(\"Hello World!\")"),
                )

                @test wait(state -> state < AWSBatch.SUCCEEDED, job; timeout=JOB_TIMEOUT)
                @test status(job) == AWSBatch.SUCCEEDED

                events = wait_for_log_events(job)
                @test length(events) == 1
                @test first(events).message == "Hello World!"

                # Test job details were set correctly
                job_details = describe(job)
                @test job_details["parameters"] == Dict(
                    "juliacmd" => "println(\"Hello World!\")"
                )

                job_definition = JobDefinition(job)
                job_definition_details = first(describe(job_definition)["jobDefinitions"])
                job_definition_details["parameters"] = Dict(
                    "juliacmd" => "println(\"Default String\")"
                )

                container_properties = job_definition_details["containerProperties"]
                @test container_properties["command"] == ["julia", "-e", "Ref::juliacmd"]

                # Deregister job definition
                deregister(job_definition)
            end

            @testset "Array job" begin
                job = run_batch(;
                    name = "aws-batch-array-job-test",
                    definition = "aws-batch-array-job-test",
                    queue = STACK["JobQueueArn"],
                    image = JULIA_BAKED_IMAGE,
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = `julia -e 'println("Hello World!")'`,
                    num_jobs = 3,
                )

                @test wait(state -> state < AWSBatch.SUCCEEDED, job; timeout=JOB_TIMEOUT)
                @test status(job) == AWSBatch.SUCCEEDED

                # Test array job was submitted properly
                status_summary = Dict(
                    "STARTING" => 0, "FAILED" => 0, "RUNNING" => 0, "SUCCEEDED" => 3,
                    "RUNNABLE" => 0, "SUBMITTED" => 0, "PENDING" => 0,
                )
                job_details = describe(job)
                @test job_details["arrayProperties"]["statusSummary"] == status_summary
                @test job_details["arrayProperties"]["size"] == 3

                # No log stream will exist for the parent job
                events = log_events(job)
                @test events === nothing

                # Test logs for each individual job that is part of the job array
                for i in 0:2
                    job_id = "$(job.id):$i"
                    events = wait_for_log_events(BatchJob(job_id))

                    @test length(events) == 1
                    @test first(events).message == "Hello World!"
                end

                # Deregister the job definition
                job_definition = JobDefinition(job)
                deregister(job_definition)
            end

            @testset "Failed Job" begin
                info(logger, "Testing job failure")

                job = run_batch(;
                    name = "aws-batch-failed-job-test",
                    definition = "aws-batch-failed-job-test",
                    queue = STACK["JobQueueArn"],
                    image = JULIA_BAKED_IMAGE,
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = `julia -e 'error("Testing job failure")'`,
                )

                job_definition = JobDefinition(job)
                @test isregistered(job_definition) == true

                @test_throws BatchJobError wait(
                    job,
                    [AWSBatch.SUCCEEDED];
                    timeout=JOB_TIMEOUT
                )

                events = wait_for_log_events(job)
                @test first(events).message == "ERROR: Testing job failure"

                deregister(job_definition)
            end
        end
    else
        warn(
            logger,
            "Skipping \"batch\" tests. Set `ENV[\"TESTS\"] = \"batch\"` and " *
            "`ENV[\"AWS_STACKNAME\"]` to run."
        )
    end
end
