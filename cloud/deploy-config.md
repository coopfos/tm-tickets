TM Tickets • Deployment Values (Fill Me In)

Purpose
- Fill in the values below, then share them so I can run `./cloud/deploy-azure.sh` for you. Each item includes where to find or decide the value in Azure.

Environment
- Suggested short code for environment (used only for labeling): `dev`, `test`, or `prod`.

Values To Provide
- Subscription ID: <paste>  
  - Where: Azure Portal > Subscriptions > select your subscription > Overview > Subscription ID.

- Tenant ID (Directory ID): <paste>  
  - Where: Azure Portal > Microsoft Entra ID > Overview > Tenant ID.  
  - Why: Needed later for iOS MSAL config; not used by the deploy script directly.

- Azure Region: <e.g., eastus2>  
  - Where: Choose a region close to users (examples: `eastus2`, `centralus`, `westus3`).

- Resource Group Name: <e.g., rg-tm-tickets-dev>  
  - Where: You can create a new RG or reuse an existing one. The script will create it if missing.

- Storage Account Name: <lowercase, unique, e.g., sttmticketsdev123>  
  - Constraints: 3–24 chars, lowercase letters and numbers only, globally unique in Azure.  
  - Where: Decide a name and the script will create it; you can confirm availability in Portal > Create storage account.

- Function App Name: <e.g., fa-tm-tickets-dev>  
  - Constraints: 2–60 chars, letters, numbers, and hyphens; must be unique across `azurewebsites.net`.  
  - Where: Decide a name and the script will create it; this becomes your base URL `https://<name>.azurewebsites.net`.

- Email Sender (UPN): <e.g., noreply@yourdomain.com>  
  - Where: Must be a real mailbox (Exchange Online) in your tenant. You’ll grant Graph Mail.Send to the Function App’s managed identity and (optionally) restrict via Exchange Application Access Policy.

- Default Email Recipients (CSV): <e.g., tickets@yourdomain.com, supervisor@yourdomain.com>  
  - Where: Any distribution list or mailbox addresses that should receive completed tickets by default.

- Email Subject Prefix (optional): <e.g., [Ticket] >  
  - Where: Free text prefix added to outgoing email subjects.

Optional (iOS Client – helps finalize MSAL)
- iOS Bundle ID: <com.yourorg.TMTickets>  
  - Where: Xcode project settings or App Store Connect.

- iOS App Registration Client ID: <paste later>  
  - Where: Entra ID > App registrations > your iOS app > Overview > Application (client) ID.  
  - Note: You’ll create this when setting up MSAL.

- Function App Web App Registration Client ID: <paste later>  
  - Where: Created when you enable Authentication (Easy Auth) on the Function App. Entra ID > App registrations > the web app created for your Function App > Overview > Application (client) ID.

- Application ID URI (API): <e.g., api://<web-app-client-id>>  
  - Where: On the Function App’s web app registration > Expose an API. You’ll add a delegated scope named `user_impersonation`.

- iOS Redirect URI: <msauth.<bundle-id>://auth>  
  - Where: Set on the iOS app registration (Platform > iOS/macOS), and add the same URL scheme to your Xcode project.

- API Scope (Delegated): <e.g., api://<web-app-client-id>/user_impersonation>  
  - Where: Once you expose the API and add the scope, grant the iOS app delegated permission to this scope.

Copy/Paste Command (will run after you provide values)
```bash
./cloud/deploy-azure.sh \
  --env dev \
  --location eastus2 \
  --resource-group rg-tm-tickets \
  --storage sttmtickets \
  --function-app tm-tickets \
  --email-sender cooper@whiteheadelectric.com \
  --default-recipients ap@whiteheadelectric.com \
  --subject-prefix WEC-TICKET 
```

After The Script (manual portal steps)
- Authentication (Easy Auth): Function App > Authentication > Add identity provider > Microsoft (Entra ID) > require auth for all requests.
- Graph Mail.Send: Entra admin center > Enterprise applications > [Function App managed identity] > Permissions > Add Microsoft Graph > Application > Mail.Send > Grant admin consent.
- Optional: Exchange Application Access Policy to restrict which mailbox the managed identity can send as.
- Expose API + Scope: On the Function App’s web app registration, set Application ID URI and add the `user_impersonation` delegated scope.
- iOS App Registration: Register native iOS app, add redirect URI (`msauth.<bundle-id>://auth`), grant delegated permission to your API’s `user_impersonation` scope.

Handy References
- Function base URL: `https://<Function App Name>.azurewebsites.net`
- Storage endpoints: `https://<Storage Account Name>.blob.core.windows.net`, `https://<Storage Account Name>.table.core.windows.net`

