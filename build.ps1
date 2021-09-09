    Clear-Host
    Remove-Item ./src/*.o
    c:/dev/cc65/bin/cl65 --verbose -o build.prg --cpu 65c02 -t cx16 -C src/cx16-asm.cfg -Ln labels.txt -m map.txt -T ./src/main.asm

if ($?)
{
    c:/dev/x16emu/x16emu -prg build.prg -debug -run -abufs 16 -scale 2 -quality nearest -echo iso
    Remove-Item ./src/*.o
} else {
    "Failed"
}