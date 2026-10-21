// Copies microphone audio (first channel) to the main thread in small blocks.
class MicTap extends AudioWorkletProcessor {
  process(inputs) {
    const channel = inputs[0]?.[0];
    if (channel) this.port.postMessage(channel.slice(0));
    return true;
  }
}

registerProcessor('mic-tap', MicTap);
