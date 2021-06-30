using OrderedCollections: OrderedDict

@testset "JobQueue" begin
    @testset "constructor" begin
        arn = "arn:aws:batch:us-east-1:000000000000:job-queue/queue"
        patch = describe_job_queues_patch(
            OrderedDict(
                "jobQueueName" => "queue-name",
                "jobQueueArn" => arn,
            )
        )

        apply(patch) do
            @test JobQueue(arn).arn == arn
        end

        apply(patch) do
            @test JobQueue("queue-name").arn == arn
        end

        patch = describe_job_queues_patch()
        apply(patch) do
            @test_throws ErrorException JobQueue("queue-name")
        end
    end

    @testset "compute_environments" begin
        # Note: to date we've only used queues with a single compute environment
        queue = JobQueue("arn:aws:batch:us-east-1:000000000000:job-queue/queue")
        patch = describe_job_queues_patch(
            OrderedDict(
                "jobQueueArn" => queue.arn,
                "computeEnvironmentOrder" => [
                    OrderedDict("order" => 2, "computeEnvironment" => "arn:aws:batch:us-east-1:000000000000:compute-environment/two"),
                    OrderedDict("order" => 1, "computeEnvironment" => "arn:aws:batch:us-east-1:000000000000:compute-environment/one"),
                ],
            )
        )

        expected = [
            ComputeEnvironment("arn:aws:batch:us-east-1:000000000000:compute-environment/one"),
            ComputeEnvironment("arn:aws:batch:us-east-1:000000000000:compute-environment/two"),
        ]

        apply(patch) do
            @test AWSBatch.compute_environments(queue) == expected
        end
    end

    @testset "max_vcpus" begin
        queue = JobQueue("arn:aws:batch:us-east-1:000000000000:job-queue/queue")
        patches = [
            describe_job_queues_patch(
                OrderedDict(
                    "jobQueueArn" => queue.arn,
                    "computeEnvironmentOrder" => [
                        OrderedDict("order" => 1, "computeEnvironment" => "arn:aws:batch:us-east-1:000000000000:compute-environment/one"),
                        OrderedDict("order" => 2, "computeEnvironment" => "arn:aws:batch:us-east-1:000000000000:compute-environment/two"),
                    ],
                )
            )
            describe_compute_environments_patch([
                OrderedDict(
                    "computeEnvironmentArn" => "arn:aws:batch:us-east-1:000000000000:compute-environment/one",
                    "computeResources" => OrderedDict("maxvCpus" => 7),
                ),
                OrderedDict(
                    "computeEnvironmentArn" => "arn:aws:batch:us-east-1:000000000000:compute-environment/two",
                    "computeResources" => OrderedDict("maxvCpus" => 8),
                )
            ])
        ]

        apply(patches) do
            @test AWSBatch.max_vcpus(queue) == 15
        end
    end
end
