function meshroomcl --description 'Startet MeshroomCL über Wine ohne Debugger-Crashes'
    cd ~/Programme/MeshroomCL/MeshroomCL-0.9.0
    env WINEDLLOVERRIDES="winedbg.exe=d" WINEPREFIX=$HOME/.wine_meshroomcl wine Meshroom.exe
end
