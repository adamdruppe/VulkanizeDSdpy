import std.stdio;
import std.exception;
import std.conv;

import base;

int main()
{
	auto app = new HelloTriangleApp();
	auto e = collectException(app.run());

	if (e)
	{
		writeln("App crashed with failure: ", e);
		return 1;
	}

	return 0;
}
