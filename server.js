const express = require('express');
const app = express();
const PORT = 3000;

// CHANGE THIS STRING to test your pipeline!
const message = "Hello from Nutanix!"; 

app.get('/', (req, res) => {
  res.send(message);
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});