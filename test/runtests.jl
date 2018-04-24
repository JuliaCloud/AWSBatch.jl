using Mocking
Mocking.enable()

using AWSBatch
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


function verify_job_submission(name, definition, queue, container, expected)
    @test name == expected["name"]
    @test definition.name == expected["definition"]
    @test queue == expected["queue"]
    @test container == expected["container"]

    return BatchJob(expected["id"])
end

function verify_job_definition(definition, image, role, vcpus, memory, cmd, expected)
    @test definition == expected["definition"]
    @test image == expected["image"]
    @test role == expected["role"]
    @test vcpus == expected["vcpus"]
    @test memory == expected["memory"]
    @test cmd == expected["cmd"]

    return JobDefinition(definition)
end


@testset "AWSBatch.jl" begin
    include("log_event.jl")
    include("job_state.jl")

    @testset "`run_batch` preprocessing" begin
        @testset "Defaults" begin
            expected_job_parameters = Dict(
                "name" => "",
                "definition" => "",
                "queue" => "",
                "container" => Dict("cmd" => ``, "memory" => 1024, "vcpus" => 1),
                "id" => "",
            )

            expected_job_definition = Dict(
                "definition" => "",
                "image" => "",
                "role" => "",
                "vcpus" => 1,
                "memory" => 1024,
                "cmd" => ``,
            )

            patches = [
                @patch register(
                    definition;
                    image="",
                    role="",
                    vcpus="",
                    memory=1024,
                    cmd=""
                ) = verify_job_definition(
                    definition,
                    image,
                    role,
                    vcpus,
                    memory,
                    cmd,
                    expected_job_definition
                )
                @patch submit(
                    name,
                    definition,
                    queue;
                    container=Dict()
                ) = verify_job_submission(
                    name,
                    definition,
                    queue,
                    container,
                    expected_job_parameters
                )
            ]

            apply(patches) do
                job = run_batch()
                @test job.id == ""
            end
        end

        @testset "From Job Definition" begin
            expected_job_parameters = Dict(
                "name" => "AWSBatchTest",
                "definition" => "sleep60",
                "queue" => "",
                "container" => Dict("cmd" => `sleep 60`, "memory" => 128, "vcpus" => 1),
                "id" => "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9",
            )

            expected_job_definition = Dict(
                "definition" => "sleep60",
                "image" => "busybox",
                "role" => "arn:aws:iam::012345678910:role/sleep60",
                "vcpus" => 1,
                "memory" => 128,
                "cmd" => `sleep 60`,
            )

            patches = [
                @patch describe_job_definitions(args...) = DESCRIBE_JOBS_DEF_RESP
                @patch job_definition_arn(definition; image="", role="") = nothing
                @patch register(
                    definition;
                    image="",
                    role="",
                    vcpus="",
                    memory=1024,
                    cmd=""
                ) = verify_job_definition(
                    definition,
                    image,
                    role,
                    vcpus,
                    memory,
                    cmd,
                    expected_job_definition
                )
                @patch submit(
                    name,
                    definition,
                    queue;
                    container=Dict()
                ) = verify_job_submission(
                    name,
                    definition,
                    queue,
                    container,
                    expected_job_parameters
                )
            ]

            apply(patches) do
                job = run_batch(; name=JOB_NAME, definition="sleep60")
                @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
            end
        end

        @testset "From Current Job" begin
            withenv(BATCH_ENVS...) do
                expected_job_parameters = Dict(
                    "name" => "example",
                    "definition" => "sleep60",
                    "queue" => "HighPriority",
                    "container" => Dict("cmd" => `sleep 60`, "memory" => 128, "vcpus" => 1),
                    "id" => "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9",
                )

                expected_job_definition = Dict(
                    "definition" => "sleep60",
                    "image" => "busybox",
                    "role" => "arn:aws:iam::012345678910:role/sleep60",
                    "vcpus" => 1,
                    "memory" => 128,
                    "cmd" => `sleep 60`,
                )

                patches = [
                    @patch describe_jobs(args...) = DESCRIBE_JOBS_RESP
                    @patch job_definition_arn(definition; image="", role="") = nothing
                    @patch register(
                        definition;
                        image="",
                        role="",
                        vcpus="",
                        memory=1024,
                        cmd=""
                    ) = verify_job_definition(
                        definition,
                        image,
                        role,
                        vcpus,
                        memory,
                        cmd,
                        expected_job_definition
                    )
                    @patch submit(
                        name,
                        definition,
                        queue;
                        container=Dict()
                    ) = verify_job_submission(
                        name,
                        definition,
                        queue,
                        container,
                        expected_job_parameters
                    )
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
