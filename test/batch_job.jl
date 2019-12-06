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
    end
end
