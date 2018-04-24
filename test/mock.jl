import Base: AbstractCmd, CmdRedirect

const BATCH_ENVS = (
    "AWS_BATCH_JOB_ID" => "24fa2d7a-64c4-49d2-8b47-f8da4fbde8e9",
    "AWS_BATCH_JQ_NAME" => "HighPriority"
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
