@testset "BatchJob" begin
    job = BatchJob("00000000-0000-0000-0000-000000000000")

    @testset "log_events" begin
        @testset "Stream not yet created" begin
            # When a AWS Batch job is first submitted the description of the job will not
            # contain a reference to a log stream
            patches = log_events_patches(log_stream_name=nothing)
            apply(patches) do
                @test log_events(job, Nothing) === nothing
            end
        end

        @testset "Stream DNE" begin
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

            patches = log_events_patches(events=() -> throw(dne_exception))
            apply(patches) do
                @test log_events(job, Nothing) === nothing  # TODO: Suppress "Fetching log events from"
            end
        end

        @testset "Stream with no events" begin
            patches = log_events_patches(events=[])
            apply(patches) do
                @test log_events(job, Nothing) == LogEvent[]
            end
        end

        @testset "Stream with events" begin
            events = [
                Dict(
                    "eventId" => "0" ^ 56,
                    "ingestionTime" => 1573672813145,
                    "timestamp" => 1573672813145,
                    "message" => "hello world!",
                )
            ]
            patches = log_events_patches(events=events)

            apply(patches) do
                @test log_events(job, Nothing) == [
                    LogEvent(
                        "0" ^ 56,
                        DateTime(2019, 11, 13, 19, 20, 13, 145),
                        DateTime(2019, 11, 13, 19, 20, 13, 145),
                        "hello world!",
                    )
                ]
            end
        end
    end
end
