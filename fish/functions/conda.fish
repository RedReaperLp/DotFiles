function conda
    # Wir löschen die Funktion temporär, um das echte conda-Binary aufzurufen
    functions -e conda

    # Initialisiere Conda (ersetze den Pfad, falls deiner anders ist!)
    # WICHTIG: Hier keine $argv einfügen!
    eval /opt/miniconda3/bin/conda "shell.fish" "hook" | source

    # Jetzt führen wir den eigentlichen Befehl aus, den du getippt hast
    conda $argv
end
