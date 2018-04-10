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
