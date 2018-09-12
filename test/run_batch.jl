function register_job_def(config::AWSConfig, input::AbstractArray, expected::AbstractArray)
    @test input == expected
    return REGISTER_JOB_DEF_RESP
end

function submit_job(config::AWSConfig, input::AbstractArray, expected::AbstractArray)
    @test input == expected
    return SUBMIT_JOB_RESP
end


@testset "run_batch" begin

    @testset "Defaults" begin
        withenv("AWS_BATCH_JOB_ID" => nothing) do
            @test_throws AWSBatch.BatchEnvironmentError run_batch()
        end
    end

    @testset "From Job Definition" begin
        expected_job = [
                "jobName" => "example",
                "jobQueue" => "HighPriority",
                "jobDefinition" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
                "parameters" => Dict{String,String}(),
                "containerOverrides" => Dict(
                    "command" => ["sleep", "60"],
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
                "jobQueue" => "HighPriority",
                "jobDefinition" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
                "parameters" => Dict{String,String}(),
                "containerOverrides" => Dict(
                    "command" => ["sleep", "60"],
                    "memory" => 128,
                    "vcpus" => 1,
                ),
            ]

            expected_job_def = [
                "type" => "container",
                "parameters" => Dict{String,String}(),
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
                @patch read(cmd::AbstractCmd, ::Type{String}) = mock_read(cmd, String)
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

    @testset "Using a Job Definition" begin
        withenv(BATCH_ENVS...) do
            expected_job = [
                "jobName" => "example",
                "jobQueue" => "HighPriority",
                "jobDefinition" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
                "parameters" => Dict{String,String}(),
                "containerOverrides" => Dict(
                    "command" => ["sleep", "60"],
                    "memory" => 128,
                    "vcpus" => 1,
                ),
            ]

            patches = [
                @patch read(cmd::AbstractCmd, ::Type{String}) = mock_read(cmd, String)
                @patch describe_jobs(args...) = DESCRIBE_JOBS_RESP
                @patch describe_job_definitions(args...) = Dict("jobDefinitions" => Dict())
                @patch submit_job(config, input) = submit_job(config, input, expected_job)
            ]

            apply(patches) do
                definition = JobDefinition("arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1")
                job = run_batch(definition=definition)
                @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
            end
        end
    end
end
