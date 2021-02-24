using OrderedCollections: OrderedDict

@testset "ComputeEnvironment" begin
    @testset "constructor" begin
        arn = "arn:aws:batch:us-east-1:000000000000:compute-environment/ce"
        @test ComputeEnvironment(arn).arn == arn

        patch = describe_compute_environments_patch(
            OrderedDict(
                "computeEnvironmentName" => "ce-name",
                "computeEnvironmentArn" => arn,
            )
        )
        apply(patch) do
            @test ComputeEnvironment("ce-name").arn == arn
        end

        patch = describe_compute_environments_patch()
        apply(patch) do
            @test_throws ErrorException ComputeEnvironment("ce-name")
        end
    end

    @testset "max_vcpus" begin
        ce = ComputeEnvironment("arn:aws:batch:us-east-1:000000000000:compute-environment/ce")
        patch = describe_compute_environments_patch(
            OrderedDict(
                "computeEnvironmentArn" => ce.arn,
                "computeResources" => OrderedDict("maxvCpus" => 5),
            ),
        )

        apply(patch) do
            @test AWSBatch.max_vcpus(ce) == 5
        end
    end
end
