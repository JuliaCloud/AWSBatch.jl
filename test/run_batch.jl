function _register_job_def(name, type, input, expected)
    @test name == expected["jobDefinitionName"]
    @test type == expected["type"]
    @test input["parameters"] == expected["parameters"]
    @test input["containerProperties"] == expected["containerProperties"]
    return REGISTER_JOB_DEF_RESP
end

function _submit_job(def, name, queue, input, expected=AbstractDict)
    @test def == expected["jobDefinition"]
    @test name == expected["jobName"]
    @test queue == expected["jobQueue"]
    @test input["parameters"] == expected["parameters"]
    @test input["containerOverrides"] == expected["containerOverrides"]
    return SUBMIT_JOB_RESP
end


@testset "run_batch" begin

    @testset "Defaults" begin
        withenv("AWS_BATCH_JOB_ID" => nothing) do
            @test_throws AWSBatch.BatchEnvironmentError run_batch()
        end
    end

    queue_arn = "arn:aws:batch:us-east-1:000000000000:job-queue/HighPriority"
    queue_patch = describe_job_queues_patch(OrderedDict("jobQueueName"=>"HighPriority",
                                                        "jobQueueArn"=>queue_arn))

    aws_config = global_aws_config()

    @testset "From Job Definition" begin
        expected_job = OrderedDict(
                "jobName" => "example",
                "jobQueue" => queue_arn,
                "jobDefinition" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
                "parameters" => Dict{String,String}(),
                "containerOverrides" => Dict(
                    "command" => ["sleep", "60"],
                    "memory" => 128,
                    "vcpus" => 1,
                ),
            )

        patches = [
            queue_patch
            @patch AWSBatch.Batch.describe_job_definitions(args...; kw...) = DESCRIBE_JOBS_DEF_RESP
            @patch AWSBatch.Batch.submit_job(def, name, queue, input; kw...) =
                _submit_job(def, name, queue, input, expected_job)
        ]

        apply(patches) do
            job = run_batch(; name="example", definition="sleep60", queue="HighPriority")
            @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
        end
    end

    @testset "From Current Job" begin
        withenv(BATCH_ENVS...) do
            expected_job = OrderedDict(
                "jobName" => "example",
                "jobQueue" => queue_arn,
                "jobDefinition" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
                "parameters" => Dict{String,String}(),
                "containerOverrides" => Dict(
                    "command" => ["sleep", "60"],
                    "memory" => 128,
                    "vcpus" => 1,
                ),
            )

            expected_job_def = OrderedDict(
                "type" => "container",
                "parameters" => Dict{String,String}(),
                "containerProperties" => OrderedDict(
                    "image" => "busybox",
                    "vcpus" => 1,
                    "memory" => 128,
                    "command" => ["sleep", "60"],
                    "jobRoleArn" => "arn:aws:iam::012345678910:role/sleep60",
                ),
                "jobDefinitionName" => "sleep60",
            )

            patches = [
                queue_patch
                @patch AWSBatch.Batch.describe_jobs(args...; kw...) = DESCRIBE_JOBS_RESP
                @patch AWSBatch.Batch.describe_job_definitions(args...; kw...) = Dict("jobDefinitions" => Dict())
                @patch AWSBatch.Batch.register_job_definition(name, type, input; kw...) =
                    _register_job_def(name, type, input, expected_job_def)
                @patch AWSBatch.Batch.submit_job(def, name, queue, input; kw...) =
                    _submit_job(def, name, queue, input, expected_job)
            ]

            apply(patches) do
                job = run_batch()
                @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
            end
        end
    end

    @testset "Using a Job Definition" begin
        withenv(BATCH_ENVS...) do
            expected_job = OrderedDict(
                "jobName" => "example",
                "jobQueue" => queue_arn,
                "jobDefinition" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
                "parameters" => Dict{String,String}(),
                "containerOverrides" => Dict(
                    "command" => ["sleep", "60"],
                    "memory" => 128,
                    "vcpus" => 1,
                ),
            )

            patches = [
                queue_patch
                @patch AWSBatch.Batch.describe_jobs(args...; kw...) = DESCRIBE_JOBS_RESP
                @patch AWSBatch.Batch.describe_job_definitions(args...; kw...) = Dict("jobDefinitions" => Dict())
                @patch AWSBatch.Batch.submit_job(def, name, queue, input; kw...) =
                    _submit_job(def, name, queue, input, expected_job)
            ]

            apply(patches) do
                definition = JobDefinition("arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1")
                job = run_batch(definition=definition)
                @test job.id == "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9"
            end
        end
    end
end
