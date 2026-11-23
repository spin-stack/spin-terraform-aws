// Two decimals on a 24- or 48-unit icon drawn at 44 to 52 px is under a hundredth of a pixel.
// multipass runs until a pass changes nothing, so a second run over the icons leaves them as they are.
export default {
  multipass: true,
  floatPrecision: 2,
  plugins: ['preset-default', 'removeTitle'],
};
