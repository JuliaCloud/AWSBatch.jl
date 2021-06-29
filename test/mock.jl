import Base: AbstractCmd, CmdRedirect
using OrderedCollections: OrderedDict

const BATCH_ENVS = (
    "AWS_BATCH_JOB_ID" => "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9",
    "AWS_BATCH_JQ_NAME" => "HighPriority"
)

const SUBMIT_JOB_RESP = Dict(
    "jobName" => "example",
    "jobId" => "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9",
)

const REGISTER_JOB_DEF_RESP = Dict(
    "jobDefinitionName" => "sleep60",
    "jobDefinitionArn" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
    "revision"=>1,
)

const DESCRIBE_JOBS_DEF_RESP = Dict(
    "jobDefinitions" => [
        Dict(
            "type" => "container",
            "containerProperties" => Dict(
                "command" => [
                    "sleep",
                    "60"
                ],
                "environment" => [

                ],
                "image" => "busybox",
                "memory" => 128,
                "mountPoints" => [

                ],
                "ulimits" => [

                ],
                "vcpus" => 1,
                "volumes" => [

                ],
                "jobRoleArn" => "arn:aws:iam::012345678910:role/sleep60",
            ),
            "jobDefinitionArn" => "arn:aws:batch:us-east-1:012345678910:job-definition/sleep60:1",
            "jobDefinitionName" => "sleep60",
            "revision" => 1,
            "status" => "ACTIVE"
        )
    ]
)

const DESCRIBE_JOBS_RESP = Dict(
    "jobs" => [
        Dict(
            "container" => Dict(
                "command" => [
                    "sleep",
                    "60"
                ],
                "containerInstanceArn" => "arn:aws:ecs:us-east-1:012345678910:container-instance/5406d7cd-58bd-4b8f-9936-48d7c6b1526c",
                "environment" => [

                ],
                "exitCode" => 0,
                "image" => "busybox",
                "memory" => 128,
                "mountPoints" => [

                ],
                "ulimits" => [

                ],
                "vcpus" => 1,
                "volumes" => [

                ],
                "jobRoleArn" => "arn:aws:iam::012345678910:role/sleep60",
            ),
            "createdAt" => 1480460782010,
            "dependsOn" => [

            ],
            "jobDefinition" => "sleep60",
            "jobId" => "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9",
            "jobName" => "example",
            "jobQueue" => "arn:aws:batch:us-east-1:012345678910:job-queue/HighPriority",
            "parameters" => Dict(

            ),
            "startedAt" => 1480460816500,
            "status" => "SUCCEEDED",
            "stoppedAt" => 1480460880699
        )
    ]
)

function describe_compute_environments_patch(output::Vector=[])
    @patch function AWSBatch.Batch.describe_compute_environments(d::Dict; aws_config)
        compute_envs = d["computeEnvironments"]
        @assert length(compute_envs) == 1
        ce = first(compute_envs)

        key = startswith(ce, "arn:") ? "computeEnvironmentArn" : "computeEnvironmentName"
        results = filter(d -> d[key] == ce, output)
        OrderedDict("computeEnvironments" => results)
    end
end

function describe_compute_environments_patch(output::OrderedDict)
    describe_compute_environments_patch([output])
end

function describe_job_queues_patch(output::Vector=[])
    @patch function AWSBatch.Batch.describe_job_queues(d::Dict; aws_config)
        queues = d["jobQueues"]
        @assert length(queues) == 1
        queue = first(queues)

        key = startswith(queue, "arn:") ? "jobQueueArn" : "jobQueueName"
        results = filter(d -> d[key] == queue, output)
        OrderedDict("jobQueues" => output)
    end
end

function describe_job_queues_patch(output::OrderedDict)
    describe_job_queues_patch([output])
end

function log_events_patches(; log_stream_name="mock_stream", events=[], exception=nothing)
    job_descriptions = if log_stream_name === nothing
        Dict("jobs" => [Dict("container" => Dict())])
    else
        Dict("jobs" => [Dict("container" => Dict("logStreamName" => log_stream_name))])
    end

    get_log_events_patch = if exception !== nothing
        @patch AWSBatch.Cloudwatch_Logs.get_log_events(args...; kwargs...) = throw(exception)
    else
        @patch function AWSBatch.Cloudwatch_Logs.get_log_events(grp, stream, params; kwargs...)
            if get(params, "nextToken", nothing) === nothing
                Dict("events" => events, "nextForwardToken" => "0")
            else
                Dict("events" => [], "nextForwardToken" => "0")
            end
        end
    end

    return [
        @patch AWSBatch.Batch.describe_jobs(args...; kwargs...) = job_descriptions
        get_log_events_patch
    ]
end
