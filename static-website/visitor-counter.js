// frontend/script.js
const incrementBtn = document.getElementById('increment-btn');
const visitorCountDisplay = document.getElementById('visitor-count');

incrementBtn.addEventListener('click', async () => {
    const response = await fetch('https://<YOUR_API_GATEWAY_ENDPOINT>/prod/count');
    const data = await response.json();
    visitorCountDisplay.innerText = data.count;
});
