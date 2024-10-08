# tablo_app

A Flutter app for connecting to and managing a Tablo DVR

## TODO
* Cache all of the above locally, update once/day (overnight?)
* Ability to rip a show
* Ability to delete a show
* Configure options to automatically export shows to NAS
* Auto delete exported shows
* Auto unschedule exported shows
* Maintain list of upcoming unscheduled shows to allow rescheduling
* Ability to force an update (partial? guide/channels/recordings?)
* Increase error handling (e.g. response includes no results, tablo down, etc)
* Add functionality to find Tablo via UDP broadcast?
* Write a service to update local database in the background?

## DONE
* ~~Find DVR on network~~
* ~~Connect to DVR~~
* ~~Download list of recordings~~
* ~~Download scheduled recordings~~
* ~~Download conflicted recordings~~
* ~~Download *everything* from the guide~~

## Thanks
* Thanks to jessedp for documenting the [Tablo API](https://github.com/jessedp/tablo-api-docs/blob/main/source/index.html.md)!