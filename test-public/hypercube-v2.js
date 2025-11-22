// 4D Hypercube (Tesseract) Animation
const canvas = document.getElementById('hypercube');
const ctx = canvas.getContext('2d');
const size = canvas.width;
const center = size / 2;

// Define the 16 vertices of a hypercube in 4D space
const vertices4D = [];
for (let i = 0; i < 16; i++) {
    vertices4D.push([
        (i & 1) ? 1 : -1,
        (i & 2) ? 1 : -1,
        (i & 4) ? 1 : -1,
        (i & 8) ? 1 : -1
    ]);
}

// Define edges (which vertices connect)
const edges = [];
for (let i = 0; i < 16; i++) {
    for (let j = i + 1; j < 16; j++) {
        // Connect vertices that differ in exactly one coordinate
        let diff = 0;
        for (let k = 0; k < 4; k++) {
            if (vertices4D[i][k] !== vertices4D[j][k]) diff++;
        }
        if (diff === 1) edges.push([i, j]);
    }
}

// Define the square faces of the hypercube
// Each face is defined by 4 vertex indices that form a square
const faces = [
    // Inner cube (w=-1) faces
    [0, 2, 6, 4],   // front
    [1, 3, 7, 5],   // back
    [0, 1, 3, 2],   // bottom
    [4, 5, 7, 6],   // top
    [0, 1, 5, 4],   // left
    [2, 3, 7, 6],   // right

    // Outer cube (w=1) faces
    [8, 10, 14, 12],   // front
    [9, 11, 15, 13],   // back
    [8, 9, 11, 10],    // bottom
    [12, 13, 15, 14],  // top
    [8, 9, 13, 12],    // left
    [10, 11, 15, 14],  // right
];

let angle = 0;

function rotate4D(point, angleXY, angleXZ, angleXW, angleYZ, angleYW, angleZW) {
    let [x, y, z, w] = point;

    // Rotate in XY plane
    let cosXY = Math.cos(angleXY), sinXY = Math.sin(angleXY);
    [x, y] = [x * cosXY - y * sinXY, x * sinXY + y * cosXY];

    // Rotate in XZ plane (front-to-back tumble)
    let cosXZ = Math.cos(angleXZ), sinXZ = Math.sin(angleXZ);
    [x, z] = [x * cosXZ - z * sinXZ, x * sinXZ + z * cosXZ];

    // Rotate in ZW plane
    let cosZW = Math.cos(angleZW), sinZW = Math.sin(angleZW);
    [z, w] = [z * cosZW - w * sinZW, z * sinZW + w * cosZW];

    return [x, y, z, w];
}

function project4Dto2D(point) {
    let [x, y, z, w] = point;

    // Project from 4D to 3D
    const distance4D = 3;
    const scale3D = distance4D / (distance4D - w);
    x *= scale3D;
    y *= scale3D;
    z *= scale3D;

    // Project from 3D to 2D
    const distance3D = 3;
    const scale2D = distance3D / (distance3D - z);
    x *= scale2D;
    y *= scale2D;

    const scale = size / 5;
    return [center + x * scale, center + y * scale];
}

function draw() {
    ctx.fillStyle = 'rgba(255, 255, 255, 0.95)';
    ctx.fillRect(0, 0, size, size);

    // Rotate and project vertices - front-to-back tumbling with 4D flow
    const projected = vertices4D.map(v => {
        // XZ for front-to-back tumble, ZW for 4D flowing-through effect
        const rotated = rotate4D(v, 0, angle, 0, 0, 0, angle * 0.5);
        return project4Dto2D(rotated);
    });

    // Draw faces with pastel colors
    faces.forEach((face, faceIndex) => {
        const hue = (angle * 50 + faceIndex * 30) % 360;
        ctx.fillStyle = `hsla(${hue}, 75%, 70%, 0.15)`;

        ctx.beginPath();
        const [x0, y0] = projected[face[0]];
        ctx.moveTo(x0, y0);
        for (let i = 1; i < face.length; i++) {
            const [x, y] = projected[face[i]];
            ctx.lineTo(x, y);
        }
        ctx.closePath();
        ctx.fill();
    });

    // Draw edges with gradient based on depth
    ctx.lineWidth = 2.5;
    edges.forEach(([i, j]) => {
        const [x1, y1] = projected[i];
        const [x2, y2] = projected[j];

        // Color based on angle for psychedelic effect
        const hue = (angle * 50 + i * 20) % 360;
        ctx.strokeStyle = `hsla(${hue}, 70%, 50%, 0.6)`;

        ctx.beginPath();
        ctx.moveTo(x1, y1);
        ctx.lineTo(x2, y2);
        ctx.stroke();
    });

    // Draw vertices
    projected.forEach((point, i) => {
        const [x, y] = point;
        const hue = (angle * 50 + i * 20) % 360;
        ctx.fillStyle = `hsl(${hue}, 70%, 50%)`;
        ctx.beginPath();
        ctx.arc(x, y, 3, 0, Math.PI * 2);
        ctx.fill();
    });

    angle += 0.01;
    requestAnimationFrame(draw);
}

draw();
