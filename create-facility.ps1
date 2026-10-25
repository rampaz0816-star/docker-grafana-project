
# ==========================================
# Create or Repair a Single Grafana Facility
# Usage:
# .\create-facility.ps1 -FacilityName "fac1"
# ==========================================

param(
    [Parameter(Mandatory=$true)]
    [string]$FacilityName,

    [Parameter(Mandatory=$true)]
    [string]$Owner
)

$ErrorActionPreference = "Stop"

# -------------------------------
# Configuration
# -------------------------------

$GrafanaURL = "http://localhost:3000"
$GrafanaUser = "admin"
$GrafanaPassword = "Abhiram@123"


$PostgresUser = "postgres"
$PostgresPassword = "Abhi@1608"
$Database = "grafana_demo"

$DatasourceName = "PostgreSQL"

# -------------------------------
# Validate and generate DB details
# -------------------------------

$SafeName = $FacilityName.ToLowerInvariant() -replace '[^a-z0-9]', '_'
$SafeName = $SafeName.Trim('_')

if ([string]::IsNullOrWhiteSpace($SafeName)) {
    throw "Facility name must contain at least one letter or number."
}

# PostgreSQL role names must begin with a letter or underscore.
if ($SafeName -notmatch '^[a-z_]') {
    $SafeName = "fac_$SafeName"
}

if ($SafeName.Length -gt 50) {
    $SafeName = $SafeName.Substring(0, 50).TrimEnd('_')
}

$DBUser = "${SafeName}_user"
$DBPassword = "${SafeName}@123"
$PolicyName = "${SafeName}_policy"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Facility Setup: $FacilityName" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# -------------------------------
# Grafana authentication
# -------------------------------

$pair = "${GrafanaUser}:${GrafanaPassword}"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
$token = [Convert]::ToBase64String($bytes)

$headers = @{
    Authorization = "Basic $token"
    "Content-Type" = "application/json"
}

# -------------------------------
# Create or find organization
# -------------------------------

$orgs = Invoke-RestMethod `
    -Uri "$GrafanaURL/api/orgs" `
    -Headers $headers `
    -Method GET

$existingOrg = $orgs | Where-Object {
    $_.name -ceq $FacilityName
} | Select-Object -First 1

if ($existingOrg) {
    $OrgID = [int]$existingOrg.id
    Write-Host "Organization already exists. ID: $OrgID"
}
else {
    $orgBody = @{ name = $FacilityName } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri "$GrafanaURL/api/orgs" `
        -Headers $headers `
        -Method POST `
        -Body $orgBody

    $OrgID = [int]$response.orgId
    Write-Host "Organization created. ID: $OrgID" -ForegroundColor Green
}

# All following datasource operations target this organization.
$orgHeaders = @{
    Authorization = "Basic $token"
    "Content-Type" = "application/json"
    "X-Grafana-Org-Id" = "$OrgID"
}

# -------------------------------
# PostgreSQL role and RLS policy
# -------------------------------


# Escape single quotes in facility name for SQL string literals.
$FacilitySQL = $FacilityName.Replace("'", "''")
$PasswordSQL = $DBPassword.Replace("'", "''")

# DBUser and PolicyName are generated from a restricted character set.
$sql = @"
DO `$block`$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = '$DBUser'
    ) THEN
        CREATE ROLE $DBUser LOGIN PASSWORD '$PasswordSQL';
    ELSE
        ALTER ROLE $DBUser LOGIN PASSWORD '$PasswordSQL';
    END IF;
END
`$block`$;

GRANT CONNECT ON DATABASE $Database TO $DBUser;
GRANT USAGE ON SCHEMA public TO $DBUser;
GRANT SELECT ON TABLE public.sensor_data TO $DBUser;

ALTER TABLE public.sensor_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "$PolicyName" ON public.sensor_data;

CREATE POLICY "$PolicyName"
ON public.sensor_data
FOR SELECT
TO $DBUser
USING (facility_name = '$FacilitySQL');
"@


$sql | docker exec -i grafana-postgres psql `
    -X `
    -v ON_ERROR_STOP=1 `
    -U $PostgresUser `
    -d $Database
    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL configuration failed. Exit code: $LASTEXITCODE"
    }


Write-Host "PostgreSQL role and RLS policy configured." -ForegroundColor Green

# -------------------------------
# Create or repair datasource
# -------------------------------

$currentDS = @(
    Invoke-RestMethod `
        -Uri "$GrafanaURL/api/datasources" `
        -Headers $orgHeaders `
        -Method GET
)

$existingDS = $currentDS | Where-Object {
    $_.name -eq $DatasourceName
} | Select-Object -First 1

$datasource = @{
    name = $DatasourceName
    type = "postgres"
    access = "proxy"
    url = "grafana-postgres:5432"
    database = $Database
    user = $DBUser
    basicAuth = $false
    isDefault = $true
    jsonData = @{
        sslmode = "disable"
        postgresVersion = 1800
        timescaledb = $false
    }
    secureJsonData = @{
        password = $DBPassword
    }
}

if ($existingDS) {
    # Update the datasource instead of skipping it.
    $datasource.id = [int]$existingDS.id

    if ($existingDS.uid) {
        $datasource.uid = $existingDS.uid
    }

    $body = $datasource | ConvertTo-Json -Depth 10

   Invoke-RestMethod `
    -Uri "$GrafanaURL/api/datasources/uid/$($existingDS.uid)" `
    -Headers $orgHeaders `
    -Method PUT `
    -Body $body | Out-Null

    Write-Host "Existing datasource repaired." -ForegroundColor Green
}
else {
    $body = $datasource | ConvertTo-Json -Depth 10

    Invoke-RestMethod `
        -Uri "$GrafanaURL/api/datasources" `
        -Headers $orgHeaders `
        -Method POST `
        -Body $body | Out-Null

Write-Host "Datasource created." -ForegroundColor Green

# ==============================
# Add User To Organization
# ==============================

$users = Invoke-RestMethod `
    -Uri "$GrafanaURL/api/users" `
    -Headers $headers `
    -Method GET

$GrafanaUserFound = $users | Where-Object {
    $_.login.Trim().ToLower() -eq $Owner.Trim().ToLower()
} | Select-Object -First 1

if ($GrafanaUserFound) {

    $memberBody = @{
        loginOrEmail = $GrafanaUserFound.login
        role = "Admin"
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Uri "$GrafanaURL/api/orgs/$OrgID/users" `
        -Headers $headers `
        -Method POST `
        -Body $memberBody | Out-Null

    Write-Host ""
    Write-Host "User added to organization successfully" -ForegroundColor Green
    Write-Host "User         : $Owner"
    Write-Host "Organization : $FacilityName"
}
else {
    Write-Host "Grafana user not found" -ForegroundColor Red
}


}

# -------------------------------
# Verify datasource in this org
# -------------------------------

$verifiedDS = @(
    Invoke-RestMethod `
        -Uri "$GrafanaURL/api/datasources" `
        -Headers $orgHeaders `
        -Method GET
)

$checkDS = $verifiedDS | Where-Object {
    $_.name -eq $DatasourceName
} | Select-Object -First 1

if (-not $checkDS) {
    throw "Datasource verification failed for organization $FacilityName."
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Facility Setup Completed" -ForegroundColor Green
Write-Host " Organization : $FacilityName"
Write-Host " Organization ID: $OrgID"
Write-Host " Database User: $DBUser"
Write-Host " Datasource   : $($checkDS.name)"
Write-Host " Datasource ID: $($checkDS.id)"
Write-Host "==========================================" -ForegroundColor Green