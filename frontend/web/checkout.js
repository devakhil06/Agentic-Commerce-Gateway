// The browser receives the public test key and server-created order only.
// A callback is sent to the backend for signature AND capture verification.
let razorpayLoading;
function loadRazorpay() {
  if (window.Razorpay) return Promise.resolve();
  if (!razorpayLoading) {
    razorpayLoading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://checkout.razorpay.com/v1/checkout.js';
      script.onload = resolve;
      script.onerror = () => { razorpayLoading = null; reject(new Error('Razorpay checkout could not load. Please retry.')); };
      document.head.appendChild(script);
    });
  }
  return razorpayLoading;
}
window.acgCheckout = async function (optionsJson) {
  await loadRazorpay();
  const options = JSON.parse(optionsJson);
  if (!options.key.startsWith('rzp_test_') || !options.order_id) throw new Error('A server-created test order is required.');
  return new Promise((resolve) => {
    const checkout = new window.Razorpay({ ...options,
      handler: response => resolve(JSON.stringify(response)),
      modal: { ondismiss: () => resolve(JSON.stringify({cancelled: true})) }
    });
    checkout.open();
  });
};
