@testset "LogEvent" begin
    @testset "constructor" begin
        event = AWSBatch.LogEvent("123", DateTime(2018, 1, 2), DateTime(2018, 1, 1), "hello world!")

        @test event.id == "123"
        @test event.ingestion_time == DateTime(2018, 1, 2)
        @test event.timestamp == DateTime(2018, 1, 1)
        @test event.message == "hello world!"
    end

    @testset "convert" begin
        d = Dict(
            "eventId" => "456",
            "ingestionTime" => 1,
            "timestamp" => 2,
            "message" => "from a dict",
        )

        event = convert(AWSBatch.LogEvent, d)

        @test event.id == "456"
        @test event.ingestion_time == DateTime(1970, 1, 1, 0, 0, 0, 1)
        @test event.timestamp == DateTime(1970, 1, 1, 0, 0, 0, 2)
        @test event.message == "from a dict"
    end

    @testset "print" begin
        event = AWSBatch.LogEvent("123", DateTime(2018, 1, 2), DateTime(2018, 1, 1), "hello world!")

        @test sprint(print, event) == "2018-01-01T00:00:00     hello world!"
        @test sprint(print, [event, event]) == """
            2018-01-01T00:00:00     hello world!
            2018-01-01T00:00:00     hello world!
            """
    end
end

@testset "log_events" begin
    @testset "Stream DNE" begin
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

        patches = log_events_patches(exception=dne_exception)
        apply(patches) do
            @test log_events("group", "dne-stream") === nothing  # TODO: Suppress "Fetching log events from"
        end
    end

    @testset "Stream with no events" begin
        patches = log_events_patches(events=[])
        apply(patches) do
            @test log_events("group", "stream") == LogEvent[]
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
            @test log_events("group", "stream") == [
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
