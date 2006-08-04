Mapper : module {
	
	map: fn(key, value: string, emit: chan of (string, string));
};

Reducer : module {
	reduce: fn(key: string, input: chan of string, emit: chan of string);
};

Reader: module {
	reader:fn(file: string, emit: chan of (string, string));
};
