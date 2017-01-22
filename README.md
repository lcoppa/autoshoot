# autoshoot
Use point and shoot cameras connected to Raspberry Pi to automatically take pictures and upload them to an ftp server of choice.

PURPOSE
To take a picture with gphoto2 by automatically adjust the exposure 
values (if the camera supports it) for day, night, sunrise and sunset.

DESCRIPTION
AUTOSHOOT takes a picture from the optionally specified USB port
in the Rasperry Pi, using gphoto2. The exposure settings are selected with the 
help of a companion script to have a better picture for day, night, and around
sunset and sunrise. The picture is saved in the current directory with the 
file name specified.

COMPATIBILIY
AUTOSHOOT is designed and tested on the Raspberry Pi rev.B,
but might work elsewhere (e.g. Pi rev. B+, BeagleBoneBlack). 
No guarantee that trapping of inconsistent parameters is complete and 
foolproof.  
It is NOT compatible with Mac OS X (as of v.10.9.4) due to incompatible 
versions of 'bash' and 'date'.
Use At Your Own Risk.
