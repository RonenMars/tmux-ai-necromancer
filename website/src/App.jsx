import Nav from './components/Nav';
import Hero from './components/Hero';
import Features from './components/Features';
import HowItWorks from './components/HowItWorks';
import Keybindings from './components/Keybindings';
import Install from './components/Install';
import Footer from './components/Footer';

export default function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Features />
        <HowItWorks />
        <Keybindings />
        <Install />
      </main>
      <Footer />
    </>
  );
}
