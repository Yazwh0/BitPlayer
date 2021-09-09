# BitPlayer

Tracker for the X16.

## Warning

This is barley more than 'Proof of Concept' code. I wouldn't even call it an alpha version. Things don't work. Things will be changed. No compatibility concerns will be given to previous versions. It may even never get an update from me.

## How To Use

For the time being I'd suggest running the player via Visual Studio 2019. Load up the solution in the WinPlayer folder.

You will need a MIDI keyboard plugged in. The application uses the first MIDI device it finds. If you have more than one, I'd suggest changing the code to select the right input device. Look for the line below.

```c#
_midiIn = new MidiIn(0);
```

If you don't have a MIDI keyboard, then you'll either need to wait or create a class that implements `IInputSource`.

## Settings

There are 4 entries that should be changed when you first get the tracker running.

Autosave: The file which gets automatically loaded and saved periodically. Very handy so we don't lose anything if the app crashes.

Filename: Simply where the 'Load' and 'Save' operate on.

Export File: The .asm file that the Export button produces. This would typically be in the source tree. Included is an example X16 application, and the default of src\player.asm would update that.

X16 Run: The powershell script to build and run your application. The default value will run the test application.

Pressing the X16 button will export the file (like pressing 'Export') and then run the X16 Run powershell script with '-ExecutionPolicy Unrestricted' in the arguments.

## X16 Code

I'd suggest opening the repository folder in Visual Studio Code to get an understanding of the X16 code. Out of the box it should run.

I'll expand on how to use the player in your own code later, but the basis is that the setup is in 'modplayer.asm', with 'display.asm' being the main application and making calls to the player.

## Commands

Commands are a work in progress. They are included in the track data in the .asm, however they are not implemented at all. Best ignore them for now.

## PCM

Not yet implmented. I'd like to know more about the hardware first. Will PCM have the total volume of all 16 PSG voices combined?

## License

All Code is licensed under GPL v3, apart from 'playertemplate.asm' or 'player.asm' is licensed with BSD 3-Clause.

This lets you use anything produced with the software with the only reistrictions being credit for the player.

Changes to the tracker itself should be given back to the community.

## Included Audio Mod

The included mod is a modified version of a song that is bundled with [FamiTracker](http://famitracker.com/), it is credited as being by 'Anon 200712', and is called 'Dubmood - 3D Galax', which is credited in the mod to Borgar Thorsteinsson. This was in turn originally written by Ben Daglish. (See this [description](https://www.youtube.com/watch?v=-2AgiLNNuuk).)
