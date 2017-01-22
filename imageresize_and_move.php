<?php

/////////////////////////////////////////////////////////////////
// Resize an image uploaded to the server
// Developed by Luca Coppadoro July 2014
////////////////////////////////////////////////////////////////


$file="webcam.jpg";		// image file
$image;
$image_file="";

if (!(is_readable($file) && is_file($file))) {
    throw new InvalidArgumentException("Image file $file is not readable");
}

// Create formatted date from the "last modified" file info (not from its exif ones)
setlocale(LC_TIME,"it_IT");
$time_from_file=strftime("%Y-%m-%d_%H-%M", filemtime($file)); 

// get image type
list ($width, $height, $type) = getimagesize($file);
switch ($type) {
    case IMAGETYPE_GIF  :
        $image = imagecreatefromgif($file);
        break;
    case IMAGETYPE_JPEG :
        $image = imagecreatefromjpeg($file);
        break;
    case IMAGETYPE_PNG  :
        $image = imagecreatefrompng($file);
        break;
    default             :
        throw new InvalidArgumentException("Image type $type not supported");
}

// resize the image
$new_width=800;
$new_height=600;
$image=imagescale($image, $new_width, $new_height, IMG_BICUBIC);

// Set output file name = file time
$image_file=$time_from_file . ".jpg";
// create the file
$quality=100; // max jpeg quality
imagejpeg($image, $image_file, $quality);
// make sure a directory for today's date exists
$today_dir="./slideshow/" . date("Y-m-d") . "/";
if ( !file_exists($today_dir) ) {
    mkdir($today_dir);
}
// move the file to the directory for today
rename($image_file, $today_dir . $image_file);


// show it for debugging
//header("Content-type: image/jpeg");
//imagejpeg($image);

// free up resources
imagedestroy($image);
?>