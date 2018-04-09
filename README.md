# Active Directory Health Check and Monitoring

## Getting Started

These instructions will get you a copy of the project up and running on your local machine where you are able to query the data from other trusted resources for development and testing purposes. See deployment for notes on how to deploy the project on a live system.

### Prerequisites

- PowerShell Version 4 at a minimum 
- Import-Module Active Directory [How to import AD Module](https://github.com/enderphan94/Learn-Power-Shell/wiki#how-to-install-ad-cmdlets)
- < Windows 7/ Windows Server 2012..
- Run as regular user

```
The tool has been tested in Windows Server 2012
```

### Installing

A step by step series of examples that tell you have to get a development env running

1. Clone it to your directory:

    `git clone https://github.com/enderphan94/AD-HCAM`
    
2. Upgrade to PowerShell 4.0 at a minimum ( if needed )

3. Import-Module Active Directory ( if needed )

## Deployment

- Service Account requirements:

In order to deploy this on a live system, you don't need an Administrator account. You can deploy it from the trusted Domain Controller where it's able to query the data from others needed DCs.
In this case a service account is required.

- Deployment processes:

1. Using Task Scheduler to run these scripts automatically.
2. Roughly 10-20 minutes is a proper time interval to implement the Health Check and Monitoring.
3. Down to Zabbix configuration will give you variety of information based on the data. 

## Built With

PowerShell Version 4.0

## Versioning

Last version updated! - Version 1.0

## Authors

* **Ender Loc Phan** - *Initial work* - [GitRespo](https://github.com/enderphan94)

## License


## Acknowledgments

* Hat tip to anyone who's code was used
* Inspiration
* etc
