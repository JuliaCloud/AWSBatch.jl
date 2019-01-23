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


"""
    Mock.read(cmd::CmdRedirect, ::Type{String})

Mocks the CmdRedirect produced from
``pipeline(`curl http://169.254.169.254/latest/meta-data/placement/availability-zone`)``
to just return "us-east-1a".
"""
function mock_read(cmd::CmdRedirect, ::Type{String})
    cmd_exec = cmd.cmd.exec
    result = if cmd_exec[1] == "curl" && occursin("availability-zone", cmd_exec[2])
        return "us-east-1a"
    else
        return Base.read(cmd, String)
    end
end


function describe_compute_environments_patch(output::Vector=[])
    @patch function describe_compute_environments(d::Dict)
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
    @patch function describe_job_queues(d::Dict)
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
