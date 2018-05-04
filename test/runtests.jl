using Mocking
Mocking.enable(force=true)

using AWSBatch
using AWSCore: AWSConfig
using AWSTools.CloudFormation: stack_output

using Base.Test
using Memento


# Enables the running of the "batch" online tests. e.g ONLINE=batch
const ONLINE = strip.(split(get(ENV, "ONLINE", ""), r"\s*,\s*"))

# Partially emulates the output from the AWS batch manager test stack
const LEGACY_STACK = Dict(
    "JobQueueArn" => "arn:aws:batch:us-east-1:292522074875:job-queue/Replatforming-Manager",
    "JobName" => "AWSBatchTest",
    "JobDefinitionName" => "AWSBatch",
    "JobRoleArn" => "arn:aws:iam::292522074875:role/AWSBatchClusterManagerJobRole",
    "EcrUri" => "292522074875.dkr.ecr.us-east-1.amazonaws.com/aws-tools:latest",
)

const AWS_STACKNAME = get(ENV, "AWS_STACKNAME", "")
const STACK = isempty(AWS_STACKNAME) ? LEGACY_STACK : stack_output(AWS_STACKNAME)

Memento.config("debug"; fmt="[{level} | {name}]: {msg}")
setlevel!(getlogger(AWSBatch), "info")

include("mock.jl")


@testset "AWSBatch.jl" begin
    include("compute_environment.jl")
    include("job_queue.jl")
    include("log_event.jl")
    include("job_state.jl")
    include("run_batch.jl")

    if "batch" in ONLINE
        @testset "Online" begin
            info("Running ONLINE tests")

            @testset "Job Submission" begin
                job = run_batch(;
                    name = STACK["JobName"],
                    definition = STACK["JobDefinitionName"],
                    queue = STACK["JobQueueArn"],
                    image = STACK["EcrUri"],
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = `julia -e 'println("Hello World!")'`,
                )

                @test wait(job, [AWSBatch.SUCCEEDED]) == true
                @test status(job) == AWSBatch.SUCCEEDED

                events = log_events(job)
                @test length(events) == 1
                @test first(events).message == "Hello World!"

                # Test job details were set correctly
                job_details = describe(job)
                @test job_details["jobName"] == STACK["JobName"]
                @test job_details["jobQueue"] == STACK["JobQueueArn"]

                # Test job definition and container parameters were set correctly
                job_definition = JobDefinition(job)
                @test isregistered(job_definition) == true

                job_definition_details = first(describe(job_definition)["jobDefinitions"])

                @test job_definition_details["jobDefinitionName"] == STACK["JobDefinitionName"]
                @test job_definition_details["status"] == "ACTIVE"
                @test job_definition_details["type"] == "container"

                container_properties = job_definition_details["containerProperties"]
                @test container_properties["image"] == STACK["EcrUri"]
                @test container_properties["vcpus"] == 1
                @test container_properties["memory"] == 1024
                @test container_properties["command"] == [
                    "julia",
                    "-e",
                    "println(\"Hello World!\")"
                ]
                @test container_properties["jobRoleArn"] == STACK["JobRoleArn"]

                deregister(job_definition)
            end

            @testset "Array job" begin
                job = run_batch(;
                    name = "AWSBatchArrayJobTest",
                    definition = STACK["JobDefinitionName"],
                    queue = STACK["JobQueueArn"],
                    image = STACK["EcrUri"],
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = `julia -e 'println("Hello World!")'`,
                    num_jobs = 3,
                )

                @test wait(job, [AWSBatch.SUCCEEDED]) == true
                @test status(job) == AWSBatch.SUCCEEDED

                # Test array job was submitted properly
                status_summary = Dict(
                    "STARTING" => 0, "FAILED" => 0, "RUNNING" => 0, "SUCCEEDED" => 3,
                    "RUNNABLE" => 0, "SUBMITTED" => 0, "PENDING" => 0,
                )
                job_details = describe(job)
                @test job_details["arrayProperties"]["statusSummary"] == status_summary
                @test job_details["arrayProperties"]["size"] == 3

                # Test no log events for the job submitted
                events = log_events(job)
                @test length(events) == 0

                # Test logs for each individual job that is part of the job array
                for i in 0:2
                    job_id = "$(job.id):$i"
                    events = log_events(BatchJob(job_id))

                    @test length(events) == 1
                    @test first(events).message == "Hello World!"
                end

                # Deregister the job definition
                job_definition = JobDefinition(job)
                deregister(job_definition)
            end

            @testset "Job Timed Out" begin
                info("Testing job timeout")

                job = run_batch(;
                    name = "AWSBatchTimeOutJobTest",
                    definition = STACK["JobDefinitionName"],
                    queue = STACK["JobQueueArn"],
                    image = STACK["EcrUri"],
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = `sleep 60`,
                )

                job_definition = JobDefinition(job)
                @test isregistered(job_definition) == true

                @test_throws ErrorException wait(job, [AWSBatch.SUCCEEDED]; timeout=0)

                deregister(job_definition)

                events = log_events(job)
                @test length(events) == 0
            end

            @testset "Failed Job" begin
                info("Testing job failure")

                job = run_batch(;
                    name = "AWSBatchFailedJobTest",
                    definition = STACK["JobDefinitionName"],
                    queue = STACK["JobQueueArn"],
                    image = STACK["EcrUri"],
                    vcpus = 1,
                    memory = 1024,
                    role = STACK["JobRoleArn"],
                    cmd = `julia -e 'error("Testing job failure")'`,
                )

                job_definition = JobDefinition(job)
                @test isregistered(job_definition) == true

                @test_throws ErrorException wait(job, [AWSBatch.SUCCEEDED])

                deregister(job_definition)

                events = log_events(job)
                @test length(events) == 3
                @test first(events).message == "ERROR: Testing job failure"
            end
        end
    else
        warn("Skipping ONLINE tests")
    end
end
