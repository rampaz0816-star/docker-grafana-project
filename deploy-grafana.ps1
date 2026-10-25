# ==========================================
# Grafana Facility User Management
# ==========================================


$UserFile = "C:\monitoring\users.json"
# ==============================
# Grafana Configuration
# ==============================

$GrafanaURL = "http://localhost:3000"

$GrafanaAdmin = "admin"
$GrafanaPassword = "Abhiram@123"


# Create Grafana API Authentication Token

$pair = "$GrafanaAdmin`:$GrafanaPassword"

$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)

$token = [Convert]::ToBase64String($bytes)


$GrafanaHeaders = @{
    Authorization = "Basic $token"
    "Content-Type" = "application/json"
}


if(!(Test-Path $UserFile))
{
    @{
        users=@()
    } | ConvertTo-Json | Set-Content $UserFile
}


$UserData = Get-Content $UserFile | ConvertFrom-Json
function Get-FacilityOwner($FacilityName){

    $allUsers = Get-Content $UserFile | ConvertFrom-Json


    foreach($user in $allUsers.users){

        if($user.facilities -contains $FacilityName){

            return $user.username

        }

    }


    return $null

}



while($true)
{

Write-Host ""
Write-Host "================================="
Write-Host "Facility Management"
Write-Host "================================="
Write-Host ""

Write-Host "1. Login"
Write-Host "2. Create New User"
Write-Host "3. Exit"

$Choice = Read-Host "Select Option"



# =========================
# CREATE USER
# =========================

if($Choice -eq "2")
{

    $Username = Read-Host "Enter Username"

    $Password = Read-Host "Enter Password"



    $exists = $UserData.users | Where-Object {

        $_.username -eq $Username

    }


    if($exists)
    {
        Write-Host "User already exists"
        continue
    }



    # Create Grafana User

    $GrafanaUserBody = @{

        name = $Username

        email = "$Username@gmail.com"

        login = $Username

        password = $Password

    } | ConvertTo-Json



    Invoke-RestMethod `
    -Uri "$GrafanaURL/api/admin/users" `
    -Headers $GrafanaHeaders `
    -Method POST `
    -Body $GrafanaUserBody



    Write-Host ""
    Write-Host "Grafana user created"



    # Save PowerShell User

    $newUser = [PSCustomObject]@{

        username = $Username

        password = $Password

        facilities = @()

    }



    $UserData.users += $newUser


    $UserData | ConvertTo-Json -Depth 10 |
    Set-Content $UserFile



    Write-Host ""
    Write-Host "User created successfully"


    continue

}


# =========================
# LOGIN
# =========================


if($Choice -eq "1")
{

    $Username = Read-Host "Enter Username"

    $Password = Read-Host "Enter Password"



    $CurrentUser = $UserData.users |
    Where-Object {

        $_.username -eq $Username -and
        $_.password -eq $Password

    }



    if(!$CurrentUser)
    {
        Write-Host "Invalid username or password"
        continue
    }



 Write-Host ""
Write-Host "Login Successful"
Write-Host "Current User : $($CurrentUser.username)"


$LoginUsername = $CurrentUser.username


break

}



if($Choice -eq "3")
{
    exit
}


}
# ==============================
# USER DASHBOARD LOOP
# ==============================

while($true){

    Write-Host ""
    Write-Host "================================="
    Write-Host "User Dashboard"
    Write-Host "================================="
    Write-Host ""
    Write-Host "1. View My Facilities"
    Write-Host "2. Create Facility"
    Write-Host "3. Delete Facility"
    Write-Host "4. Change User"
    Write-Host "5. Logout"
    Write-Host ""

    $UserAction = Read-Host "Select Option"


    # -----------------------------
    # View Facilities
    # -----------------------------

    if($UserAction -eq "1"){

        Write-Host ""
        Write-Host "Your Facilities:"
        Write-Host ""

        if($CurrentUser.facilities.Count -eq 0){

            Write-Host "No facilities assigned"

        }
        else{

            foreach($facility in $CurrentUser.facilities){

                Write-Host "- $facility"

            }

        }

    }


    # -----------------------------
    # Create Facility
    # -----------------------------

    elseif($UserAction -eq "2"){


        $FacilityName = Read-Host "Enter Facility Name"
$Owner = Get-FacilityOwner $FacilityName


if($Owner){

    Write-Host ""
    Write-Host "Facility already belongs to user: $Owner"

    continue

}


        if([string]::IsNullOrWhiteSpace($FacilityName)){

            Write-Host "Facility name cannot be empty"
            continue

        }


        Write-Host ""
        Write-Host "Creating facility..."


& "C:\monitoring\create-facility.ps1" `
-FacilityName $FacilityName `
-Owner $CurrentUser.username



        # Reload users file

        $UserData = Get-Content $UserFile | ConvertFrom-Json


       $CurrentUser = $UserData.users | Where-Object {

    $_.username -eq $LoginUsername

}


if($null -eq $CurrentUser.facilities){

    $CurrentUser | Add-Member `
    -MemberType NoteProperty `
    -Name facilities `
    -Value @()

}


$CurrentUser.facilities += $FacilityName



        $UserData | ConvertTo-Json -Depth 10 | Set-Content $UserFile



        Write-Host ""
        Write-Host "Facility added successfully"
        Write-Host "Owner : $LoginUsername"

    }



    # -----------------------------
    # Delete Facility
    # -----------------------------

    elseif($UserAction -eq "3"){


        if($CurrentUser.facilities.Count -eq 0){

            Write-Host "No facilities available"
            continue

        }


        Write-Host ""
        Write-Host "Your Facilities:"


        $index=1


        foreach($facility in $CurrentUser.facilities){

            Write-Host "$index. $facility"

            $index++

        }



        $deleteChoice = Read-Host "Select Facility Number"



        $DeleteFacility = $CurrentUser.facilities[$deleteChoice-1]



        if($DeleteFacility){


            Write-Host ""
            Write-Host "Deleting $DeleteFacility..."
$Owner = Get-FacilityOwner $DeleteFacility


if($Owner -ne $LoginUsername){

    Write-Host ""
    Write-Host "Access denied"
    Write-Host "Facility belongs to: $Owner"

    continue

}



            & "C:\monitoring\delete-facility.ps1" `
            -FacilityName $DeleteFacility



            $CurrentUser.facilities = @(
            
                $CurrentUser.facilities | Where-Object {
                    $_ -ne $DeleteFacility
                }

            )



            $UserData | ConvertTo-Json -Depth 10 | Set-Content $UserFile



            Write-Host ""
            Write-Host "Facility removed"

        }

    }



    # -----------------------------
    # Change User
    # -----------------------------

    elseif($UserAction -eq "4"){

        Write-Host ""
        Write-Host "Changing user..."

        break

    }



    # -----------------------------
    # Logout
    # -----------------------------

    elseif($UserAction -eq "5"){


        Write-Host ""
        Write-Host "Logged out"

        exit

    }


}