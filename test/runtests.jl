using Mocking
Mocking.enable()

using AWSBatch
using AWSCore: AWSConfig

using Base.Test
using Memento

const IMAGE_DEFINITION = "292522074875.dkr.ecr.us-east-1.amazonaws.com/aws-tools:latest"
const JOB_ROLE = "arn:aws:iam::292522074875:role/AWSBatchClusterManagerJobRole"
const JOB_DEFINITION = "AWSBatch"
const JOB_NAME = "AWSBatchTest"
const JOB_QUEUE = "Replatforming-Manager"

Memento.config("debug"; fmt="[{level} | {name}]: {msg}")
setlevel!(getlogger(AWSBatch), "info")

include("mock.jl")


function register_job_def(config::AWSConfig, input::AbstractArray, expected::AbstractArray)
    @test input == expected
    return REGISTER_JOB_DEF_RESP
end

function submit_job(config::AWSConfig, input::AbstractArray, expected::AbstractArray)
    @test input == expected

    cmd = Dict(input)["containerOverrides"]["cmd"]
    @spawn run(cmd)

    return SUBMIT_JOB_RESP
end


@testset "AWSBatch.jl" begin
    include("log_event.jl")
    include("job_state.jl")

    @testset "`run_batch` preprocessing" begin

        @testset "Defaults" begin
            withenv("AWS_BATCH_JOB_ID" => nothing) do
                @test_throws AWSBatch.BatchEnvironmentError run_batch()
            end
        end

        @testset "From Job Definition" begin
            expected_job = [
                    "jobName" => "example",
                    "jobDefinition" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
                    "jobQueue" => "HighPriority",
                    "containerOverrides" => Dict(
                        "cmd" => `sleep 60`,
                        "memory" => 128,
                        "vcpus" => 1,
                    ),
                ]

            patches = [
                @patch describe_job_definitions(args...) = DESCRIBE_JOBS_DEF_RESP
                @patch submit_job(config, input) = submit_job(config, input, expected_job)
            ]

            apply(patches) do
                job = run_batch(; name="example", definition="sleep60", queue="HighPriority")
                @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
            end
        end

        @testset "From Current Job" begin
            withenv(BATCH_ENVS...) do
                expected_job = [
                    "jobName" => "example",
                    "jobDefinition" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
                    "jobQueue" => "HighPriority",
                    "containerOverrides" => Dict(
                        "cmd" => `sleep 60`,
                        "memory" => 128,
                        "vcpus" => 1,
                    ),
                ]

                expected_job_def = [
                    "type" => "container",
                    "containerProperties" => [
                        "image" => "busybox",
                        "vcpus" => 1,
                        "memory" => 128,
                        "command" => ["sleep", "60"],
                        "jobRoleArn" => "arn:aws:iam::012345678910:role/sleep60",
                    ],
                    "jobDefinitionName" => "sleep60",
                ]

                patches = [
                    @patch readstring(cmd::AbstractCmd) = mock_readstring(cmd)
                    @patch describe_jobs(args...) = DESCRIBE_JOBS_RESP
                    @patch describe_job_definitions(args...) = Dict("jobDefinitions" => Dict())
                    @patch register_job_definition(config, input) = register_job_def(
                        config,
                        input,
                        expected_job_def,
                    )
                    @patch submit_job(config, input) = submit_job(config, input, expected_job)
                ]

                apply(patches) do
                     job = run_batch()
                     @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
                end
            end
        end
    end

    @testset "Online" begin
        info("Running ONLINE tests")

        @testset "Job Submission" begin
            job = run_batch(;
                name = JOB_NAME,
                definition = JOB_DEFINITION,
                queue = JOB_QUEUE,
                image = IMAGE_DEFINITION,
                vcpus = 1,
                memory = 1024,
                role = JOB_ROLE,
                cmd = `julia -e 'println("Hello World!")'`,
            )

            @test wait(job, [AWSBatch.SUCCEEDED]) == true
            @test status(job) == AWSBatch.SUCCEEDED

            # Test job details were set correctly
            job_details = describe(job)
            @test job_details["jobName"] == JOB_NAME
            @test job_details["jobQueue"] == (
                "arn:aws:batch:us-east-1:292522074875:job-queue/Replatforming-Manager"
            )

            # Test job definition and container parameters were set correctly
            job_definition = JobDefinition(job_details["jobDefinition"])
            @test isregistered(job_definition) == true

            job_definition_details = first(describe(job_definition)["jobDefinitions"])

            @test job_definition_details["jobDefinitionName"] == JOB_DEFINITION
            @test job_definition_details["status"] == "ACTIVE"
            @test job_definition_details["type"] == "container"

            container_properties = job_definition_details["containerProperties"]
            @test container_properties["image"] == IMAGE_DEFINITION
            @test container_properties["vcpus"] == 1
            @test container_properties["memory"] == 1024
            @test container_properties["command"] == [
                "julia",
                "-e",
                "println(\"Hello World!\")"
            ]
            @test container_properties["jobRoleArn"] == JOB_ROLE

            deregister(job_definition)

            events = log_events(job)
            @test length(events) == 1
            @test contains(first(events).message, "Hello World!")
        end

        @testset "Job Timed Out" begin
            job = run_batch(;
                name = JOB_NAME,
                definition = JOB_DEFINITION,
                queue = JOB_QUEUE,
                image = IMAGE_DEFINITION,
                vcpus = 1,
                memory = 1024,
                role = JOB_ROLE,
                cmd = `sleep 60`,
            )

            job_definition = JobDefinition(describe(job)["jobDefinition"])
            @test isregistered(job_definition) == true

            info("Testing job timeout")
            @test_throws ErrorException wait(job, [AWSBatch.SUCCEEDED]; timeout=0)

            deregister(job_definition)

            events = log_events(job)
            @test length(events) == 0
        end

        @testset "Failed Job" begin
            job = run_batch(;
                name = JOB_NAME,
                definition = JOB_DEFINITION,
                queue = JOB_QUEUE,
                image = IMAGE_DEFINITION,
                vcpus = 1,
                memory = 1024,
                role = JOB_ROLE,
                cmd = `julia -e 'error("Cmd failed")'`,
            )

            job_definition = JobDefinition(describe(job)["jobDefinition"])
            @test isregistered(job_definition) == true

            info("Testing job failure")
            @test_throws ErrorException wait(job, [AWSBatch.SUCCEEDED])

            deregister(job_definition)

            events = log_events(job)
            @test length(events) == 3
            @test contains(first(events).message, "ERROR: Cmd failed")
        end
    end
end
