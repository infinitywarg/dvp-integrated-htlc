// Function to recursively read files in a directory
function readFiles(dir) {
    fs.readdir(dir, (err, files) => {
        if (err) {
            console.error('Error reading directory:', err);
            return;
        }

        files.forEach(file => {
            const filePath = path.join(dir, file);

            fs.stat(filePath, (err, stats) => {
                if (err) {
                    console.error('Error getting file stats:', err);
                    return;
                }

                if (stats.isDirectory()) {
                    readFiles(filePath); // Recursively read subdirectory
                } else if (stats.isFile()) {
                    fs.readFile(filePath, 'utf8', (err, data) => {
                        if (err) {
                            console.error('Error reading file:', err);
                            return;
                        }
                        console.log(`Contents of ${filePath}:`);
                        console.log(data); // Print file contents
                    });
                }
            });
        });
    });
}
