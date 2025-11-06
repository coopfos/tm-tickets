using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

public class TicketsFunctions
{
    private readonly ILogger<TicketsFunctions> _logger;

    public TicketsFunctions(ILogger<TicketsFunctions> logger)
    {
        _logger = logger;
    }

    [Function("Ping")]
    public async Task<HttpResponseData> Ping(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "ping")] HttpRequestData req)
    {
        _logger.LogInformation("Ping endpoint invoked");
        var res = req.CreateResponse(HttpStatusCode.OK);
        await res.WriteStringAsync("OK");
        return res;
    }
}
