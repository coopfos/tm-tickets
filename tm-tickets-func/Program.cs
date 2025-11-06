using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
  .ConfigureFunctionsWorkerDefaults()
  .ConfigureServices(s => s.AddSingleton<SqlFactory>())
  .Build();

host.Run();

public class SqlFactory {
  readonly string _host = Environment.GetEnvironmentVariable("SqlServer__Host")!;
  readonly string _db   = Environment.GetEnvironmentVariable("SqlServer__Db")!;
  readonly DefaultAzureCredential _cred = new();
  public async Task<SqlConnection> OpenAsync() {
    var token = (await _cred.GetTokenAsync(new TokenRequestContext(new[] { "https://database.windows.net//.default" }))).Token;
    var conn = new SqlConnection($"Server=tcp:{_host},1433;Database={_db};Encrypt=True;TrustServerCertificate=False;");
    conn.AccessToken = token;
    await conn.OpenAsync();
    return conn;
  }
}