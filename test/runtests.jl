using Mocking
Mocking.enable()

using AWSBatch
using Base.Test
using Memento
using AWSSDK

import AWSSDK.Batch: describe_job_definitions

const PKG_DIR = abspath(dirname(@__FILE__), "..")
const REV = cd(() -> readchomp(`git rev-parse HEAD`), PKG_DIR)
const IMAGE_DEFINITION = "292522074875.dkr.ecr.us-east-1.amazonaws.com/aws-tools:latest"
const JOB_ROLE = "arn:aws:iam::292522074875:role/AWSBatchClusterManagerJobRole"
const JOB_DEFINITION = "AWSBatch"
const JOB_NAME = "AWSBatchTest"
const JOB_QUEUE = "Replatforming-Manager"

Memento.config("debug"; fmt="[{level} | {name}]: {msg}")
setlevel!(getlogger(AWSBatch), "info")

include("mock.jl")

@testset "AWSBatch.jl" begin
    @testset "Job Construction" begin
        @testset "Defaults" begin
            job = BatchJob()

            @test isempty(job.id)
            @test isempty(job.name)
            @test isempty(job.queue)
            @test isempty(job.region)

            @test isempty(job.definition.name)

            @test isempty(job.container.image)
            @test job.container.vcpus == 1
            @test job.container.memory == 1024
            @test isempty(job.container.role)
            @test isempty(job.container.cmd)
        end

        @testset "From Job Definition" begin
            patch = @patch describe_job_definitions(args...) = DESCRIBE_JOBS_DEF_RESP

            apply(patch; debug=true) do
                job = BatchJob(name=JOB_NAME, definition="sleep60")

                @test isempty(job.id)
                @test job.name == "AWSBatchTest"
                @test isempty(job.queue)
                @test isempty(job.region)

                @test job.definition.name == "sleep60"

                @test job.container.image == "busybox"
                @test job.container.vcpus == 1
                @test job.container.memory == 128
                @test job.container.role == "arn:aws:iam::012345678910:role/sleep60"
                @test job.container.cmd == `sleep 60`
            end
        end

        @testset "From Current Job" begin
            withenv(BATCH_ENVS...) do
                patches = [
                    @patch readstring(cmd::AbstractCmd) = mock_readstring(cmd)
                    @patch describe_jobs(args...) = DESCRIBE_JOBS_RESP
                ]

                apply(patches; debug=true) do
                    job = BatchJob()

                    @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
                    @test job.name == "example"
                    @test job.queue == "HighPriority"
                    @test job.region == "us-east-"

                    @test job.definition.name == "sleep60"


                    @test job.container.image == "busybox"
                    @test job.container.vcpus == 1
                    @test job.container.memory == 128
                    @test job.container.role == "arn:aws:iam::012345678910:role/sleep60"
                    @test job.container.cmd == `sleep 60`
                end
            end
        end

        @testset "From Multiple" begin
            withenv(BATCH_ENVS...) do
                patches = [
                    @patch readstring(cmd::AbstractCmd) = mock_readstring(cmd)
                    @patch describe_jobs(args...) = DESCRIBE_JOBS_RESP
                ]

                apply(patches; debug=true) do
                    job = BatchJob()

                    @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
                    @test job.name == "example"
                    @test job.definition.name == "sleep60"
                    @test job.queue == "HighPriority"
                    @test job.region == "us-east-"

                    @test job.container.image == "busybox"
                    @test job.container.vcpus == 1
                    @test job.container.memory == 128
                    @test job.container.role == "arn:aws:iam::012345678910:role/sleep60"
                    @test job.container.cmd == `sleep 60`
                end
            end
        end

        @testset "Reuse job definition" begin
            withenv(BATCH_ENVS...) do
                patches = [
                    @patch readstring(cmd::AbstractCmd) = mock_readstring(cmd)
                    @patch describe_jobs(args...) = DESCRIBE_JOBS_RESP
                ]

                apply(patches; debug=true) do
                    job = BatchJob()

                    @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
                    @test job.name == "example"
                    @test job.definition.name == "sleep60"
                    @test job.queue == "HighPriority"
                    @test job.region == "us-east-"

                    @test job.container.image == "busybox"
                    @test job.container.vcpus == 1
                    @test job.container.memory == 128
                    @test job.container.role == "arn:aws:iam::012345678910:role/sleep60"
                    @test job.container.cmd == `sleep 60`
                end
            end
        end

    end

    @testset "Job Submission" begin
        job = BatchJob(;
            name = JOB_NAME,
            definition = JOB_DEFINITION,
            queue = JOB_QUEUE,
            container = Dict(
                "image" => IMAGE_DEFINITION,
                "vcpus" => 1,
                "memory" => 1024,
                "role" => JOB_ROLE,
                "cmd" => `julia -e 'println("Hello World!")'`,
            ),
        )

        submit(job)
        @test isregistered(job) == true
        @test wait(job, [AWSBatch.SUCCEEDED]) == true
        deregister!(job)
        events = logs(job)

        @test length(events) == 1
        @test contains(first(events)["message"], "Hello World!")
    end

    @testset "Job Timed Out" begin
        job = BatchJob(;
            name = JOB_NAME,
            definition = JOB_DEFINITION,
            queue = JOB_QUEUE,
            container = Dict(
                "image" => IMAGE_DEFINITION,
                "vcpus" => 1,
                "memory" => 1024,
                "role" => JOB_ROLE,
                "cmd" => `sleep 60`,
            ),
        )

        submit(job)
        @test isregistered(job) == true
        @test_throws ErrorException wait(job, [AWSBatch.SUCCEEDED]; timeout=0)
        deregister!(job)
        events = logs(job)

        @test length(events) == 0
    end

    @testset "Failed Job" begin
        job = BatchJob(;
            name = JOB_NAME,
            definition = JOB_DEFINITION,
            queue = JOB_QUEUE,
            container = Dict(
                "image" => IMAGE_DEFINITION,
                "vcpus" => 1,
                "memory" => 1024,
                "role" => JOB_ROLE,
                "cmd" => `julia -e 'error("Cmd failed")'`,
            ),
        )

        submit(job)
        @test isregistered(job) == true
        @test_throws ErrorException wait(job, [AWSBatch.SUCCEEDED])
        deregister!(job)
        events = logs(job)

        @test length(events) == 3
        @test contains(first(events)["message"], "ERROR: Cmd failed")
    end
end
