@testset "BatchJob" begin
    job = BatchJob("00000000-0000-0000-0000-000000000000")

    @testset "log_events" begin
        @testset "Log stream not yet created" begin
            # When a AWS Batch job is first submitted the description of the job will not
            # contain a reference to a log stream
            patch = @patch describe_jobs(args...; kwargs...) = Dict(
                "jobs" => [Dict("container" => Dict())]
            )
            apply(patch) do
                @test log_events(job, Nothing) === nothing
            end
        end

        @testset "Log stream does not exist" begin
            # The AWS Batch job references a log stream but the stream has not yet been
            # created.
            dne_exception = AWSException(
                HTTP.StatusError(
                    400,
                    "",
                    "",
                    HTTP.Messages.Response(
                        400,
                        Dict("Content-Type" => "application/x-amz-json-1.1");
                        body="""{"__type":"ResourceNotFoundException","message":"The specified log stream does not exist."}"""
                    )
                )
            )

            patches = [
                @patch describe_jobs(args...; kwargs...) = Dict(
                    "jobs" => [Dict("container" => Dict("logStreamName" => ""))]
                )
                @patch get_log_events(; kwargs...) = throw(dne_exception)
            ]
            apply(patches) do
                @test log_events(job, Nothing) === nothing  # TODO: Suppress "Fetching log events from"
            end
        end
    end
end
