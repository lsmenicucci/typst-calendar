ALWAYS: ;

docs: ALWAYS
	typst compile usage.typ docs/usage.pdf
	typst compile --input split=true usage.typ docs/usage-{0p}.png --ppi 144

